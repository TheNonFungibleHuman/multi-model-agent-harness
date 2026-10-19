#!/usr/bin/env python3
"""Search the harness skill shelf without loading it into the prompt.

The shelf packs live under ~/grok-skill-shelf/<pack>/<skill>/SKILL.md and are
deliberately not linked into ~/.grok/skills. This script reads their names and
descriptions on demand and prints ranked candidates with absolute paths.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SHELF = Path.home() / "grok-skill-shelf"


def _parse_frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end < 0:
        return {}
    block = text[3:end]
    data: dict[str, str] = {}
    lines = block.splitlines()
    i = 0
    while i < len(lines):
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", lines[i])
        if not m:
            i += 1
            continue
        key, val = m.group(1), m.group(2).strip()
        if val in (">", "|", ">-", "|-"):
            buf = []
            i += 1
            while i < len(lines) and (lines[i].startswith((" ", "\t")) or not lines[i].strip()):
                if lines[i].strip():
                    buf.append(lines[i].strip())
                i += 1
            data[key] = " ".join(buf)
            continue
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        data[key] = val
        i += 1
    return data


def collect(include_core: bool) -> list[dict]:
    if not SHELF.is_dir():
        return []
    out = []
    for pack_dir in sorted(SHELF.iterdir()):
        if not pack_dir.is_dir() or pack_dir.name.startswith("_") or pack_dir.name == "firecrawl":
            continue
        if pack_dir.name == "core" and not include_core:
            continue
        for skill_dir in sorted(pack_dir.iterdir()):
            f = skill_dir / "SKILL.md"
            if not f.is_file():
                continue
            try:
                text = f.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            fm = _parse_frontmatter(text)
            name = fm.get("name") or skill_dir.name
            out.append({
                "name": name,
                "pack": pack_dir.name,
                "folder": skill_dir.name,
                "path": str(f),
                "description": fm.get("description", "").strip(),
                "user_only": fm.get("disable-model-invocation", "").strip().lower() == "true",
            })
    return out


def score(query: str, skill: dict) -> int:
    q = query.lower().strip()
    if not q:
        return 0
    terms = [t for t in re.split(r"[^a-z0-9]+", q) if len(t) > 1]
    name = skill["name"].lower()
    pack = skill["pack"].lower()
    hay = f"{name} {pack} {skill['description'].lower()}"
    total = 0
    for t in terms:
        variants = {t, t[:-1]} if len(t) > 3 and t.endswith("s") else {t}
        if any(v in name for v in variants):
            total += 8
        if any(v in pack for v in variants):
            total += 3
        total += min(max(hay.count(v) for v in variants), 4) * 2
    if q in hay:
        total += 10
    return total


def line(skill: dict, limit: int = 150) -> str:
    desc = " ".join(skill["description"].split())
    if len(desc) > limit:
        desc = desc[: limit - 1] + "…"
    flag = " [user-only]" if skill["user_only"] else ""
    return f"{skill['name']:<28} {skill['pack']:<12} {skill['path']}{flag}\n    {desc}"


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="Search the skill shelf")
    ap.add_argument("query", nargs="?", default="", help="what you need")
    ap.add_argument("--list", action="store_true", help="list all skills")
    ap.add_argument("--pack", help="only this pack")
    ap.add_argument("--show", help="show one skill by name")
    ap.add_argument("--max", type=int, default=6)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--include-core", action="store_true")
    args = ap.parse_args()

    skills = collect(args.include_core)
    if args.pack:
        skills = [s for s in skills if s["pack"] == args.pack]
    if args.show:
        skills = [s for s in skills if s["name"] == args.show]
    if args.query and not args.list:
        skills = [s for s in skills if score(args.query, s) > 0]
        skills.sort(key=lambda s: score(args.query, s), reverse=True)
    else:
        skills.sort(key=lambda s: (s["pack"], s["name"]))
    skills = skills[: args.max]

    if args.json:
        print(json.dumps(skills, indent=1))
    else:
        if not skills:
            print("no matches; try --list or a broader query")
        for s in skills:
            print(line(s))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
