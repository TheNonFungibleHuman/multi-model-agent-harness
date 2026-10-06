#!/usr/bin/env python3
"""
token-ledger: token-usage ledger for Grok Build on DeepSeek seats.

Tails ~/.grok/logs/unified.jsonl and appends one row per
shell.turn.inference_done to usage.jsonl, then refreshes report.md.

  Grok writes unified.jsonl  ->  ledger.py  ->  usage.jsonl + report.md

Usage:
  ledger.py             daemon loop (tail + periodic report refresh)
  ledger.py --once      scan what is new since the last offset, then exit
  ledger.py --report    regenerate report.md from usage.jsonl + session stats, then exit

Cost model (deepseek-v4-flash, per 1M tokens, fetched from api-docs.deepseek.com):
  input cache hit   $0.0028
  input cache miss  $0.14
  output            $0.28   (completion + reasoning; never cached)

State:
  ledger.state   last byte offset read from unified.jsonl
  usage.jsonl    one JSON row per inference
  session_stats.jsonl  per-session aggregates from sessions/*/signals.json
  report.md      human-readable weekly summary
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

GROK_HOME = Path(os.environ.get("GROK_HOME", Path.home() / ".grok"))
LOG_FILE = GROK_HOME / "logs" / "unified.jsonl"
SESSIONS_DIR = GROK_HOME / "sessions"
LEDGER_DIR = GROK_HOME / "token-ledger"
STATE_FILE = LEDGER_DIR / "ledger.state"
USAGE_FILE = LEDGER_DIR / "usage.jsonl"
STATS_FILE = LEDGER_DIR / "session_stats.jsonl"
REPORT_FILE = LEDGER_DIR / "report.md"

POLL_SECS = 5
REPORT_REFRESH_SECS = 900  # 15 min

# deepseek-v4 pricing (USD per 1M tokens) — confirmed against the official
# usage export price column and api-docs.deepseek.com.
PRICES = {
    "deepseek-v4-flash": {"hit": 0.0028, "miss": 0.14, "out": 0.28},
    "deepseek-v4-pro": {"hit": 0.003625, "miss": 0.435, "out": 0.87},
}
DEFAULT_PRICE = PRICES["deepseek-v4-flash"]

DEEPSEEK_PREFIXES = ("deepseek-v4", "deepseek-")


def price_for(model: str | None) -> dict:
    if model and "pro" in model.lower():
        return PRICES["deepseek-v4-pro"]
    return DEFAULT_PRICE


def utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def est_cost_usd(prompt: int, cached: int, completion: int, reasoning: int, model: str | None = None) -> float:
    p = price_for(model)
    miss = max(0, prompt - cached)
    return (miss * p["miss"] + cached * p["hit"] + (completion + reasoning) * p["out"]) / 1e6


def is_deepseek_model(model: str | None) -> bool:
    if not model:
        return False
    m = model.lower()
    return any(m.startswith(p) for p in DEEPSEEK_PREFIXES)


def free_models() -> set:
    """Model strings listed under [free_models] in overrides.toml — seats that
    cost nothing (e.g. a free opencode-zen DeepSeek seat). Excluded from the
    estimated USD totals."""
    ov = LEDGER_DIR / "overrides.toml"
    if not ov.exists():
        return set()
    try:
        import tomllib
    except ImportError:
        return set()
    try:
        with ov.open("rb") as f:
            data = tomllib.load(f)
    except (tomllib.TOMLDecodeError, OSError):
        return set()
    return {str(m).lower() for m in (data.get("free_models") or {}).get("models", [])}


def parse_inference(line: str, sid_models: dict[str, str], free: set) -> dict | None:
    """Parse a shell.turn.inference_done line into a usage row, or None."""
    try:
        rec = json.loads(line)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None
    if rec.get("msg") != "shell.turn.inference_done":
        return None
    ctx = rec.get("ctx") or {}
    if "prompt_tokens" not in ctx:
        return None
    prompt = int(ctx.get("prompt_tokens", 0))
    cached = int(ctx.get("cached_prompt_tokens", 0))
    completion = int(ctx.get("completion_tokens", 0))
    reasoning = int(ctx.get("reasoning_tokens", 0))
    sid = rec.get("sid") or ""
    # Inference rows carry no model id; attribute via the session's primary
    # model from signals.json. Unknown sessions default to the main DeepSeek seat.
    model = sid_models.get(sid, "deepseek-v4-flash")
    deepseek = is_deepseek_model(model) and model.lower() not in free
    return {
        "ts": rec.get("ts") or utcnow_iso(),
        "sid": sid,
        "pid": rec.get("pid"),
        "loop_index": ctx.get("loop_index"),
        "model": model,
        "prompt_tokens": prompt,
        "cached_tokens": cached,
        "miss_tokens": max(0, prompt - cached),
        "completion_tokens": completion,
        "reasoning_tokens": reasoning,
        "deepseek": deepseek,
        "est_cost_usd": round(est_cost_usd(prompt, cached, completion, reasoning, model), 6),
    }


def sid_primary_models() -> dict[str, str]:
    """sid -> primary model, from session_stats.jsonl (refreshed by scan_signals)."""
    out: dict[str, str] = {}
    if not STATS_FILE.exists():
        return out
    with STATS_FILE.open("r", encoding="utf-8") as f:
        for line in f:
            try:
                r = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                continue
            if r.get("sid") and r.get("primary_model"):
                out[r["sid"]] = r["primary_model"]
    return out


def read_seen_keys() -> set:
    keys: set[tuple] = set()
    if not USAGE_FILE.exists():
        return keys
    with USAGE_FILE.open("r", encoding="utf-8") as f:
        for line in f:
            try:
                r = json.loads(line)
                keys.add((r.get("ts"), r.get("pid"), r.get("loop_index"), r.get("sid")))
            except (json.JSONDecodeError, ValueError):
                continue
    return keys


def append_rows(rows: list[dict]) -> None:
    if not rows:
        return
    with USAGE_FILE.open("a", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


def scan_log_once() -> int:
    """Append new inference rows from unified.jsonl since the stored offset."""
    if not LOG_FILE.exists():
        return 0
    size = LOG_FILE.stat().st_size
    offset = 0
    if STATE_FILE.exists():
        try:
            offset = int(STATE_FILE.read_text().strip())
        except ValueError:
            offset = 0
    if size < offset:
        # Log rotated/truncated: re-scan from the top; dedup keeps rows unique.
        offset = 0
    seen = read_seen_keys()
    sid_models = sid_primary_models()
    free = free_models()
    new_rows: list[dict] = []
    with LOG_FILE.open("r", encoding="utf-8", errors="replace") as f:
        f.seek(offset)
        for line in f:
            row = parse_inference(line, sid_models, free)
            if row is None:
                continue
            key = (row["ts"], row["pid"], row["loop_index"], row["sid"])
            if key in seen:
                continue
            seen.add(key)
            new_rows.append(row)
    append_rows(new_rows)
    STATE_FILE.write_text(str(LOG_FILE.stat().st_size))
    return len(new_rows)


def scan_signals() -> int:
    """Aggregate sessions/*/signals.json into session_stats.jsonl (dedup by sid)."""
    if not SESSIONS_DIR.exists():
        return 0
    seen: set = set()
    if STATS_FILE.exists():
        with STATS_FILE.open("r", encoding="utf-8") as f:
            for line in f:
                try:
                    seen.add(json.loads(line).get("sid"))
                except (json.JSONDecodeError, ValueError):
                    continue
    written = 0
    with STATS_FILE.open("a", encoding="utf-8") as out:
        for sig in SESSIONS_DIR.glob("*/*/signals.json"):
            sid = sig.parent.name
            if sid in seen:
                continue
            try:
                s = json.loads(sig.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                continue
            if not isinstance(s, dict) or "turnCount" not in s:
                continue
            summary_path = sig.parent / "summary.json"
            updated_at = None
            if summary_path.exists():
                try:
                    updated_at = json.loads(summary_path.read_text(encoding="utf-8")).get("updated_at")
                except (json.JSONDecodeError, OSError):
                    pass
            row = {
                "sid": sid,
                "ts": updated_at,
                "turns": s.get("turnCount", 0),
                "tool_calls": s.get("toolCallCount", 0),
                "context_tokens_used": s.get("contextTokensUsed", 0),
                "compactions": s.get("compactionCount", 0),
                "long_pauses": s.get("longPausesCount", 0),
                "errors": s.get("errorCount", 0),
                "models": s.get("modelsUsed", []),
                "primary_model": s.get("primaryModelId"),
            }
            out.write(json.dumps(row, ensure_ascii=False) + "\n")
            written += 1
    return written


def load_usage(days: int | None = None) -> list[dict]:
    rows: list[dict] = []
    if not USAGE_FILE.exists():
        return rows
    cutoff = None
    if days is not None:
        cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    with USAGE_FILE.open("r", encoding="utf-8") as f:
        for line in f:
            try:
                r = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                continue
            if cutoff is not None:
                try:
                    ts = datetime.fromisoformat(r.get("ts", "").replace("Z", "+00:00"))
                    if ts < cutoff:
                        continue
                except ValueError:
                    pass
            rows.append(r)
    return rows


def load_stats(days: int | None = None) -> list[dict]:
    rows: list[dict] = []
    if not STATS_FILE.exists():
        return rows
    cutoff = None
    if days is not None:
        cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    with STATS_FILE.open("r", encoding="utf-8") as f:
        for line in f:
            try:
                r = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                continue
            if cutoff is not None and r.get("ts"):
                try:
                    ts = datetime.fromisoformat(str(r["ts"]).replace("Z", "+00:00"))
                    if ts < cutoff:
                        continue
                except ValueError:
                    pass
            rows.append(r)
    return rows


def fmt_usd(x: float) -> str:
    return f"${x:,.4f}"


def load_official() -> dict:
    """Parse the DeepSeek usage export CSVs (copied to usage_export/).
    Returns {day: {model: {hit, miss, output, requests, cost}}} with
    per-row type counts keyed by the CSV's own (UTC+4) day labels."""
    export = LEDGER_DIR / "usage_export"
    if not export.exists():
        return {}
    cost_rows: list[dict] = []
    amount_rows: list[dict] = []
    for f in export.glob("*.csv"):
        try:
            lines = f.read_text(encoding="utf-8-sig").splitlines()
        except OSError:
            continue
        header = lines[0].split(",")
        for line in lines[1:]:
            parts = line.split(",")
            if len(parts) != len(header):
                continue
            row = dict(zip(header, parts))
            if "cost" in row:
                cost_rows.append(row)
            if "type" in row:
                amount_rows.append(row)
    out: dict[str, dict] = {}
    for r in cost_rows:
        day = r.get("start_time_iso", "")[:10]
        model = r.get("model", "?")
        try:
            cost = float(r.get("cost", "0"))
        except ValueError:
            cost = 0.0
        d = out.setdefault(day, {}).setdefault(model, {"hit": 0, "miss": 0, "output": 0, "requests": 0, "cost": 0.0})
        d["cost"] += cost
    for r in amount_rows:
        day = r.get("start_time_iso", "")[:10]
        model = r.get("model", "?")
        t = r.get("type", "")
        try:
            amount = int(float(r.get("amount", "0")))
        except ValueError:
            amount = 0
        d = out.setdefault(day, {}).setdefault(model, {"hit": 0, "miss": 0, "output": 0, "requests": 0, "cost": 0.0})
        if t == "input_cache_hit_tokens":
            d["hit"] += amount
        elif t == "input_cache_miss_tokens":
            d["miss"] += amount
        elif t == "output_tokens":
            d["output"] += amount
        elif t == "request_count":
            d["requests"] += amount
    return out


def write_report() -> None:
    usage = load_usage(days=7)
    stats = load_stats(days=7)
    lines: list[str] = []
    lines.append("# Grok Build token ledger")
    lines.append("")
    lines.append(f"Generated: {utcnow_iso()}")
    lines.append(f"Rows: {len(usage)} inferences (7d), {len(stats)} sessions (7d)")
    lines.append("")
    lines.append("Rates used: flash hit $0.0028/M, miss $0.14/M, output $0.28/M; "
                 "pro hit $0.003625/M, miss $0.435/M, output $0.87/M (confirmed vs the official export).")
    lines.append("")
    if usage:
        total_prompt = sum(r["prompt_tokens"] for r in usage)
        total_cached = sum(r["cached_tokens"] for r in usage)
        total_miss = sum(r["miss_tokens"] for r in usage)
        total_completion = sum(r["completion_tokens"] for r in usage)
        total_reasoning = sum(r["reasoning_tokens"] for r in usage)
        ds_cost = sum(r["est_cost_usd"] for r in usage if r.get("deepseek"))
        hit_pct = 100.0 * total_cached / total_prompt if total_prompt else 0.0
        lines.append("## 7-day totals")
        lines.append("")
        lines.append(f"- Input tokens: {total_prompt:,}  (cache hit {total_cached:,} / {hit_pct:.1f}%)")
        lines.append(f"- Un-cached input tokens: {total_miss:,}")
        lines.append(f"- Output tokens: {total_completion:,}  (+ reasoning {total_reasoning:,})")
        lines.append(f"- Est. DeepSeek cost (7d): **{fmt_usd(ds_cost)}**")
        lines.append("")
        # Per-day breakdown
        by_day: dict[str, dict] = {}
        for r in usage:
            day = r["ts"][:10]
            d = by_day.setdefault(day, {"prompt": 0, "cached": 0, "miss": 0, "out": 0, "reason": 0, "cost": 0.0, "deep": False})
            d["prompt"] += r["prompt_tokens"]
            d["cached"] += r["cached_tokens"]
            d["miss"] += r["miss_tokens"]
            d["out"] += r["completion_tokens"]
            d["reason"] += r["reasoning_tokens"]
            if r.get("deepseek"):
                d["cost"] += r["est_cost_usd"]
                d["deep"] = True
        lines.append("## Per day")
        lines.append("")
        lines.append("| Day | Input | Cached % | Miss | Output | Reasoning | Est $ (DeepSeek) |")
        lines.append("|---|---|---|---|---|---|---|")
        for day in sorted(by_day):
            d = by_day[day]
            pct = 100.0 * d["cached"] / d["prompt"] if d["prompt"] else 0.0
            lines.append(
                f"| {day} | {d['prompt']:,} | {pct:.1f}% | {d['miss']:,} | {d['out']:,} | {d['reason']:,} | {fmt_usd(d['cost']) if d['deep'] else 'n/a'} |"
            )
        lines.append("")
    if stats:
        lines.append("## Sessions (7d, from signals.json)")
        lines.append("")
        lines.append("| Session | Turns | Tool calls | Peak context | Compactions | Long pauses |")
        lines.append("|---|---|---|---|---|---|")
        for s in sorted(stats, key=lambda x: -(x.get("context_tokens_used") or 0))[:15]:
            lines.append(
                f"| {s['sid'][-8:]} | {s.get('turns', 0)} | {s.get('tool_calls', 0)} | "
                f"{s.get('context_tokens_used', 0):,} | {s.get('compactions', 0)} | {s.get('long_pauses', 0)} |"
            )
        lines.append("")
    official = load_official()
    if official:
        lines.append("## Official spend (DeepSeek usage export)")
        lines.append("")
        lines.append("Source: `token-ledger/usage_export/*.csv`. Days are the export's own UTC+4 day labels.")
        lines.append("")
        lines.append("| Day | Model | Cache hit | Cache miss | Output | Requests | Cost (USD) |")
        lines.append("|---|---|---|---|---|---|---|")
        total_cost = 0.0
        for day in sorted(official):
            for model in sorted(official[day]):
                d = official[day][model]
                total_cost += d["cost"]
                lines.append(
                    f"| {day} | {model} | {d['hit']:,} | {d['miss']:,} | {d['output']:,} | "
                    f"{d['requests']:,} | {fmt_usd(d['cost'])} |"
                )
        lines.append(f"| **Total** | | | | | | **{fmt_usd(total_cost)}** |")
        lines.append("")
        obs_cost = sum(r["est_cost_usd"] for r in usage if r.get("deepseek"))
        lines.append(
            f"Harness-observed estimate for the same period: {fmt_usd(obs_cost)} "
            "(ledger covers only what the harness logged — unified.jsonl starts 2026-08-12T03:30Z; "
            "the export is the billing source of truth)."
        )
        lines.append("")
    REPORT_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")


def daemon_loop() -> None:
    LEDGER_DIR.mkdir(parents=True, exist_ok=True)
    last_report = 0.0
    while True:
        try:
            n = scan_log_once()
            scan_signals()
            now = time.monotonic()
            if n or (now - last_report) >= REPORT_REFRESH_SECS:
                write_report()
                last_report = now
        except Exception as e:  # noqa: BLE001 - daemon must survive transient errors
            print(f"[token-ledger] error: {e}", flush=True)
        time.sleep(POLL_SECS)


def main() -> None:
    ap = argparse.ArgumentParser(description="Grok Build token ledger")
    ap.add_argument("--once", action="store_true", help="scan new log lines once and exit")
    ap.add_argument("--report", action="store_true", help="regenerate report.md and exit")
    args = ap.parse_args()

    LEDGER_DIR.mkdir(parents=True, exist_ok=True)
    if args.report:
        scan_signals()
        write_report()
        print(f"[token-ledger] report written: {REPORT_FILE}")
        return
    if args.once:
        n = scan_log_once()
        scan_signals()
        write_report()
        print(f"[token-ledger] appended {n} rows; report refreshed")
        return
    daemon_loop()


if __name__ == "__main__":
    main()
