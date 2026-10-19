#!/usr/bin/env python3
"""Regenerate the always-loaded lessons digest from ~/.grok/lessons/LESSONS.md.

Full lessons live in LESSONS.md; this writes a short, newest-first digest to
~/.grok/rules/03-lessons.md so the next session starts with the durable rules
without loading the whole log.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

HOME = Path.home()
DEFAULT_SOURCE = HOME / ".grok" / "lessons" / "LESSONS.md"
DEFAULT_OUT = HOME / ".grok" / "rules" / "03-lessons.md"
MAX_ITEMS = 12
MAX_CHARS = 240


def _clean(text: str) -> str:
    # The live LESSONS.md has a few mojibake sequences from older writes.
    return text.replace("\ufffd?\"", "-").replace("\ufffd", "-")


def parse(source: Path) -> list[tuple[str, str]]:
    if not source.is_file():
        return []
    text = source.read_text(encoding="utf-8", errors="replace")
    entries: list[tuple[str, str]] = []
    current = None
    for line in text.splitlines():
        m = re.match(r"^##+\s+(.+?)\s*$", line)
        if m:
            current = (m.group(1), "")
            entries.append(current)
            continue
        if current and not current[1]:
            r = re.match(r"^\s*[-*]?\s*\*{0,2}Rule:?\*{0,2}\s*(.+?)\s*$", line, re.IGNORECASE)
            if r:
                entries[-1] = (current[0], r.group(1))
    return [(t, r) for t, r in entries if r][:MAX_ITEMS]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default=str(DEFAULT_SOURCE))
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    args = ap.parse_args()

    source = Path(args.source)
    out = Path(args.out)
    items = parse(source)
    lines = [
        "# Lessons digest (auto-generated)",
        "<!-- source: ~/.grok/lessons/LESSONS.md; regenerate with lessons-digest.py -->",
    ]
    if not items:
        lines.append("No lessons captured yet.")
    for title, rule in items:
        title = _clean(" ".join(title.split()))
        rule = _clean(" ".join(rule.split()))
        if len(rule) > MAX_CHARS:
            rule = rule[: MAX_CHARS - 1] + "…"
        lines.append(f"- **{title}** — {rule}")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"lessons digest: {len(items)} item(s) -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
