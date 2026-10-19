#!/usr/bin/env python3
"""Print trajectory metrics grouped by model from ~/.grok/metrics/sessions.jsonl."""
from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

DEFAULT = Path.home() / ".grok" / "metrics" / "sessions.jsonl"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default=str(DEFAULT))
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    p = Path(args.file)
    if not p.is_file():
        print(f"no metrics file: {p}")
        return 1

    rows = []
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.strip():
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                pass

    groups: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        groups[r.get("model") or "unknown"].append(r)

    def avg(xs, key):
        vals = [x.get(key) for x in xs if isinstance(x.get(key), (int, float))]
        return round(sum(vals) / len(vals), 1) if vals else None

    out = []
    for model, xs in sorted(groups.items()):
        out.append({
            "model": model,
            "sessions": len(xs),
            "avg_turns": avg(xs, "turns"),
            "avg_tool_calls": avg(xs, "tool_calls"),
            "avg_context_pct": avg(xs, "context_pct"),
            "avg_duration_s": avg(xs, "duration_s"),
            "total_tokens": sum(x.get("context_tokens") or 0 for x in xs),
            "total_lines": sum((x.get("lines_added") or 0) + (x.get("lines_removed") or 0) for x in xs),
        })

    if args.json:
        print(json.dumps(out, indent=1))
    else:
        print(f"metrics: {len(rows)} session(s) from {p}")
        print(f"{'model':<24} {'n':>3} {'turns':>6} {'tools':>6} {'ctx%':>6} {'dur(s)':>7} {'tokens':>12}")
        for r in out:
            print(f"{r['model']:<24} {r['sessions']:>3} {str(r['avg_turns']):>6} {str(r['avg_tool_calls']):>6} "
                  f"{str(r['avg_context_pct']):>6} {str(r['avg_duration_s']):>7} {r['total_tokens']:>12}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
