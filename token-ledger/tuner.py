#!/usr/bin/env python3
"""
auto-tuner: keeps Grok Build config.toml token-lean, automatically.

Reads usage.jsonl + session_stats.jsonl (written by ledger.py) and, within
hard bounds, adjusts ~/.grok/config.toml:

  - context_window  (every [model.*] seat that declares one): raised toward
    524288 when sessions hug the ceiling (compaction risk) or a session
    compacts 3+ times in a day. Step 65536, at most one change per seat per
    24h, and never lowered: the key sets when Grok auto-compacts, so lowering
    it saves no tokens and only makes compaction fire sooner. Takes effect on
    the next session.
  - default_reasoning_effort: pinned to "low" when reasoning-token burn is
    a large share of output; never raised automatically.
  - MCP hygiene: keeps paper / gemini-docs disabled once repeated handshake
    failures are seen in unified.jsonl.

Every change is appended to changes.log; a timestamped config backup is made
before the first edit. Values pinned in overrides.toml are never touched.

Usage:
  tuner.py            one tuning pass, then exit (call from a scheduler)
  tuner.py --loop     every 15 minutes
  tuner.py --dry-run  report what would change without editing
"""

from __future__ import annotations

import argparse
import json
import os
import re
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

try:  # Python 3.11+
    import tomllib
except ImportError:  # pragma: no cover - older interpreters skip validation
    tomllib = None

GROK_HOME = Path(os.environ.get("GROK_HOME", Path.home() / ".grok"))
CONFIG_FILE = GROK_HOME / "config.toml"
LOG_FILE = GROK_HOME / "logs" / "unified.jsonl"
LEDGER_DIR = GROK_HOME / "token-ledger"
USAGE_FILE = LEDGER_DIR / "usage.jsonl"
STATS_FILE = LEDGER_DIR / "session_stats.jsonl"
CHANGES_LOG = LEDGER_DIR / "changes.log"
OVERRIDES_FILE = LEDGER_DIR / "overrides.toml"
BASELINE_FILE = LEDGER_DIR / "baseline.state"

LOOP_SECS = 900  # 15 min

# Hard bounds for automatic context_window tuning (tokens).
WINDOW_FLOOR = 131072  # verifier-enforced lower bound; the tuner only raises
WINDOW_CAP = 524288
WINDOW_STEP = 65536
# Thresholds (fractions of the current declared window).
RAISE_AT = 0.80    # avg peak context above this -> raise window
MIN_SESSIONS = 3   # require at least this many sessions before tuning

# MCP sections whose repeated failures may auto-disable them. Only optional
# servers belong here: disabling a core tool (exa) on a transient error would
# silently break search. gemini-docs was retired 2026-09-10 and is no longer listed.
MCP_WATCH = ("mcp_servers.paper",)


def watched_servers() -> tuple[str, ...]:
    """Bare server names derived from MCP_WATCH, so the watch list lives once."""
    return tuple(s.removeprefix("mcp_servers.") for s in MCP_WATCH)

def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


# ---------------------------------------------------------------- config editing

def parse_toml_sections(lines: list[str]) -> list[tuple[str | None, str]]:
    """Return (section, line) pairs; section is the innermost [table] header."""
    out: list[tuple[str | None, str]] = []
    section: str | None = None
    for line in lines:
        m = re.match(r"^\s*\[([^\]]+)\]\s*$", line)
        if m:
            section = m.group(1).strip()
        out.append((section, line))
    return out


def set_value(lines: list[str], sections: tuple[str, ...], key: str, new_value: str) -> list[str]:
    """Replace `key = ...` inside the given sections. Returns updated lines."""
    pattern = re.compile(rf"^(\s*{re.escape(key)}\s*=\s*).*$")
    out = list(lines)
    for i, (section, line) in enumerate(parse_toml_sections(lines)):
        if section in sections and pattern.match(line):
            out[i] = pattern.sub(rf"\g<1>{new_value}", line)
    return out


def read_config_lines() -> list[str]:
    if not CONFIG_FILE.exists():
        raise FileNotFoundError(f"config not found: {CONFIG_FILE}")
    return CONFIG_FILE.read_text(encoding="utf-8").splitlines()


def current_values(lines: list[str]) -> dict[str, str]:
    vals: dict[str, str] = {}
    for section, line in parse_toml_sections(lines):
        if section and section.startswith("model."):
            m = re.match(r"^\s*context_window\s*=\s*(\d+)", line)
            if m:
                vals[f"window:{section}"] = m.group(1)
        if section == "models":
            m = re.match(r"^\s*default_reasoning_effort\s*=\s*\"([^\"]+)\"", line)
            if m:
                vals["reasoning:models"] = m.group(1)
        if section in MCP_WATCH:
            m = re.match(r"^\s*enabled\s*=\s*(true|false)", line)
            if m:
                vals[f"mcp:{section}"] = m.group(1)
    return vals


def managed_seats(lines: list[str]) -> list[str]:
    """Every [model.*] section that declares a context_window. The tuner bounds
    all of them so no seat can silently run unbounded."""
    seats: list[str] = []
    for section, line in parse_toml_sections(lines):
        if section and section.startswith("model.") and re.match(r"^\s*context_window\s*=", line):
            if section not in seats:
                seats.append(section)
    return seats


def last_change_ts(key: str) -> str | None:
    """Most recent changes.log timestamp for a key, or None."""
    if not CHANGES_LOG.exists():
        return None
    last: str | None = None
    with CHANGES_LOG.open("r", encoding="utf-8") as f:
        for line in f:
            parts = line.split(" | ")
            if len(parts) >= 2 and parts[1] == key:
                last = parts[0]
    return last


def changed_within_24h(key: str) -> bool:
    ts = last_change_ts(key)
    if not ts:
        return False
    try:
        t = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return False
    return (datetime.now(timezone.utc) - t) < timedelta(hours=24)


def apply_changes(changes: dict[str, tuple[str, str, str]], dry_run: bool) -> None:
    """changes: key -> (section, old, new). Writes config + log; backs up once."""
    if not changes:
        return
    lines = read_config_lines()
    if not dry_run:
        backup = CONFIG_FILE.with_name(f"config.toml.bak-{datetime.now().strftime('%Y%m%d-%H%M%S')}")
        if not list(CONFIG_FILE.parent.glob("config.toml.bak-*")):
            backup.write_text(CONFIG_FILE.read_text(encoding="utf-8"), encoding="utf-8")
    entries: list[str] = []
    for key, (section, old, new) in changes.items():
        if key.startswith("window:"):
            lines = set_value(lines, (section,), "context_window", str(new))
        elif key == "reasoning:models":
            lines = set_value(lines, ("models",), "default_reasoning_effort", f'"{new}"')
        elif key.startswith("mcp:"):
            lines = set_value(lines, (section,), "enabled", new)
        entries.append(f"{now_iso()} | {key} | {old} -> {new} | reason: {section}")
    if not dry_run:
        text = "\n".join(lines) + "\n"
        # Never write a config the harness cannot load: a bad rewrite here is
        # invisible until a session misbehaves. Validate, then commit.
        if tomllib is not None:
            try:
                tomllib.loads(text)
            except Exception as e:  # noqa: BLE001 - any parse failure must block the write
                print(f"[auto-tuner] REFUSING to write invalid TOML ({e}); config left unchanged", flush=True)
                return
        CONFIG_FILE.write_text(text, encoding="utf-8", newline="\n")
        with CHANGES_LOG.open("a", encoding="utf-8") as f:
            for e in entries:
                f.write(e + "\n")
        print(f"[auto-tuner] applied {len(entries)} change(s): {', '.join(e.split(' | ')[1] for e in entries)}")
    else:
        print("[auto-tuner] DRY-RUN would change:")
        for e in entries:
            print("  " + e)


# ---------------------------------------------------------------- metrics

def load_rows(path: Path, days: int) -> list[dict]:
    if not path.exists():
        return []
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    rows: list[dict] = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            try:
                r = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                continue
            if r.get("ts"):
                try:
                    ts = datetime.fromisoformat(str(r["ts"]).replace("Z", "+00:00"))
                    if ts < cutoff:
                        continue
                except ValueError:
                    pass
            rows.append(r)
    return rows


def filter_after(rows: list[dict], ts: str) -> list[dict]:
    """Keep rows at/after ts (UTC ISO). Rows without a parseable ts are kept."""
    try:
        cutoff = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return rows
    out: list[dict] = []
    for r in rows:
        if not r.get("ts"):
            out.append(r)
            continue
        try:
            rts = datetime.fromisoformat(str(r["ts"]).replace("Z", "+00:00"))
        except ValueError:
            out.append(r)
            continue
        if rts >= cutoff:
            out.append(r)
    return out


def ensure_baseline(dry_run: bool) -> str:
    """Baseline = first tuning pass after the config fix. Rows before it are
    artifacts of the unbounded-window era and must not drive tuning."""
    existing = None
    if BASELINE_FILE.exists():
        existing = BASELINE_FILE.read_text().strip()
    if existing:
        return existing
    ts = now_iso()
    if not dry_run:
        BASELINE_FILE.write_text(ts)
        with CHANGES_LOG.open("a", encoding="utf-8") as f:
            f.write(f"{ts} | baseline | - | {ts} | tuning inputs start at baseline (post-fix behavior)\n")
    return ts


def mcp_failures_24h() -> dict[str, int]:
    """Count handshake/connection failures for watched MCP servers in the log."""
    if not LOG_FILE.exists():
        return {}
    counts: dict[str, int] = {}
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=24)).isoformat() + "Z"
    with LOG_FILE.open("r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if "mcp" not in line.lower():
                continue
            if '"lvl":"info"' in line or '"lvl":"debug"' in line:
                continue
            try:
                rec = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                continue
            ts = rec.get("ts") or ""
            if ts < cutoff:
                continue
            blob = (line + " " + json.dumps(rec.get("ctx") or {})).lower()
            for server in watched_servers():
                if server in blob and any(k in blob for k in ("fail", "error", "refused", "handshake", "unreachable", "timeout")):
                    counts[server] = counts.get(server, 0) + 1
    return counts


def load_overrides() -> dict:
    if not OVERRIDES_FILE.exists():
        return {}
    try:
        import tomllib  # Python 3.11+
    except ImportError:
        return {}
    try:
        with OVERRIDES_FILE.open("rb") as f:
            return tomllib.load(f)
    except (tomllib.TOMLDecodeError, OSError):
        return {}


# ---------------------------------------------------------------- tuning pass

def tune(dry_run: bool) -> None:
    baseline = ensure_baseline(dry_run)
    usage = filter_after(load_rows(USAGE_FILE, days=1), baseline)
    stats = filter_after(load_rows(STATS_FILE, days=1), baseline)
    lines = read_config_lines()
    current = current_values(lines)
    overrides = load_overrides()
    changes: dict[str, tuple[str, str, str]] = {}

    # Per-seat context window: use peak context per active session (all rows;
    # unknown-model rows default to the DeepSeek seat in the ledger).
    compactions_24h = [s.get("compactions", 0) for s in stats]
    raise_signal = any(c >= 3 for c in compactions_24h)
    if usage:
        peak_by_sid: dict[str, int] = {}
        for r in usage:
            peak_by_sid[r.get("sid")] = max(peak_by_sid.get(r.get("sid"), 0), r.get("prompt_tokens", 0))
        sessions = [p for p in peak_by_sid.values() if p > 0]
        if len(sessions) >= MIN_SESSIONS:
            avg_peak = sum(sessions) / len(sessions)
            for seat in managed_seats(lines):
                key = f"window:{seat}"
                cur = int(current.get(key, "262144"))
                pin = (overrides.get("context_window") or {}).get(seat.removeprefix("model."))
                if pin or changed_within_24h(key):
                    continue
                if (raise_signal or avg_peak > RAISE_AT * cur) and cur < WINDOW_CAP:
                    new = min(cur + WINDOW_STEP, WINDOW_CAP)
                    changes[key] = (seat, str(cur), str(new))

    # Reasoning effort: pin low when reasoning is a big share of output.
    deep_rows = [r for r in usage if r.get("deepseek")]
    if deep_rows:
        total_out = sum(r["completion_tokens"] + r["reasoning_tokens"] for r in deep_rows)
        total_reason = sum(r["reasoning_tokens"] for r in deep_rows)
        if total_out > 0 and total_reason / total_out > 0.20:
            cur = current.get("reasoning:models", "medium")
            pin = overrides.get("reasoning", {}).get("default_reasoning_effort")
            # Any pin means hands off, matching how context_window pins behave.
            # Before this, only pinning "low" had an effect, so a "medium" pin
            # in overrides.toml was silently ignored.
            if cur != "low" and pin is None:
                changes["reasoning:models"] = ("models", cur, "low")

    # MCP hygiene.
    failures = mcp_failures_24h()
    for server in watched_servers():
        section = f"mcp_servers.{server}"
        key = f"mcp:{section}"
        cur = current.get(key, "true")
        pin = (overrides.get("mcp") or {}).get(server)
        if failures.get(server, 0) >= 3 and cur != "false" and pin is not False:
            changes[key] = (section, cur, "false")

    apply_changes(changes, dry_run)


def main() -> None:
    ap = argparse.ArgumentParser(description="Grok Build auto-tuner")
    ap.add_argument("--loop", action="store_true", help="run every 15 minutes")
    ap.add_argument("--dry-run", action="store_true", help="report without editing")
    args = ap.parse_args()

    if args.loop:
        while True:
            try:
                tune(dry_run=False)
            except Exception as e:  # noqa: BLE001 - daemon must survive transient errors
                print(f"[auto-tuner] error: {e}", flush=True)
            time.sleep(LOOP_SECS)
    else:
        tune(dry_run=args.dry_run)


if __name__ == "__main__":
    main()
