#!/usr/bin/env python3
"""Carry the auto-tuner's live values across a profile switch.

`switch-profile.ps1` installs a template (config.lean.toml / config.full.toml)
over the live config.toml, which used to silently discard every tuning decision
the auto-tuner had made. This re-applies the live values onto the new file:

  - model.<seat>.context_window        (every seat the tuner bounds)
  - models.default_reasoning_effort
  - mcp_servers.<watched>.enabled

Values pinned in overrides.toml never reach the live file, so carrying the live
value carries the pin too. A section the template does not declare is reported
and left alone.

Usage:
  carry_tuning.py --template ~/.grok/config.lean.toml
  carry_tuning.py --template ~/.grok/config.full.toml --dry-run
"""

from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime
from pathlib import Path

LEDGER_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(LEDGER_DIR))
import tuner  # noqa: E402  (path-dependent import by design)

CONFIG = tuner.CONFIG_FILE


def value_in(lines: list[str], kind: str, section: str) -> str | None:
    """Current value of `kind` inside `section`, or None when not declared."""
    for sec, line in tuner.parse_toml_sections(lines):
        if sec != section:
            continue
        if kind == "default_reasoning_effort":
            m = re.match(r'^\s*default_reasoning_effort\s*=\s*"([^"]+)"', line)
        else:
            m = re.match(rf"^\s*{re.escape(kind)}\s*=\s*([^\s#]+)", line)
        if m:
            return m.group(1).strip('"')
    return None


def live_values(lines: list[str]) -> dict[tuple[str, str], str]:
    vals: dict[tuple[str, str], str] = {}
    for section, line in tuner.parse_toml_sections(lines):
        if not section:
            continue
        if section.startswith("model."):
            v = value_in(lines, "context_window", section)
            if v is not None:
                vals[("context_window", section)] = v
        elif section == "models":
            v = value_in(lines, "default_reasoning_effort", "models")
            if v is not None:
                vals[("default_reasoning_effort", "models")] = v
        elif section in tuner.MCP_WATCH:
            v = value_in(lines, "enabled", section)
            if v is not None:
                vals[("enabled", section)] = v
    return vals


def main() -> int:
    ap = argparse.ArgumentParser(description="Carry auto-tuner values onto a config profile")
    ap.add_argument("--template", required=True, type=Path)
    ap.add_argument("--active", default=CONFIG, type=Path)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not args.template.is_file():
        print(f"[carry-tuning] missing template: {args.template}", file=sys.stderr)
        return 1

    live = live_values(args.active.read_text(encoding="utf-8").splitlines()) if args.active.is_file() else {}
    lines = args.template.read_text(encoding="utf-8").splitlines()

    carried: list[str] = []
    same: list[str] = []
    absent: list[str] = []
    for (kind, section), value in sorted(live.items()):
        current = value_in(lines, kind, section)
        if current is None:
            absent.append(f"{kind}:{section}")
            continue
        if current == value:
            same.append(f"{kind}:{section}")
            continue
        rendered = f'"{value}"' if kind == "default_reasoning_effort" else value
        target = ("models",) if kind == "default_reasoning_effort" else (section,)
        lines = tuner.set_value(lines, target, kind, rendered)
        carried.append(f"{kind}:{section} {current} -> {value}")

    print(f"[carry-tuning] template {args.template.name}: "
          f"{len(carried)} carried, {len(same)} already equal, {len(absent)} not declared")
    for line in carried:
        print(f"  {line}")
    if absent:
        print(f"  not in template (left at template default): {', '.join(absent)}")

    if args.dry_run or not carried:
        return 0

    if args.active.is_file():
        backup = args.active.with_name(f"{args.active.name}.bak-switch-{datetime.now().strftime('%Y%m%d-%H%M%S')}")
        backup.write_text(args.active.read_text(encoding="utf-8"), encoding="utf-8")
        print(f"  backup: {backup.name}")
    args.active.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"  wrote {args.active}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
