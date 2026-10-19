#!/usr/bin/env python3
"""Hard anti-slop gate for Grok Build.

Stop hook (no args): reads the event JSON on stdin, scans UI files changed in
the project, and blocks the stop while the Impeccable detector finds issues.
Pre-commit mode (--staged): scans staged UI files and exits 2 on findings.

The detector is deterministic and local; no API key, no model call.
"""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HOME = Path.home()
DETECTOR = HOME / "grok-skill-shelf" / "design" / "impeccable" / "scripts" / "impeccable.cmd"
UI_EXT = {
    ".html", ".htm", ".css", ".scss", ".sass", ".less",
    ".tsx", ".jsx", ".vue", ".svelte", ".astro", ".php", ".mdx",
}
MAX_FILES = 20
MAX_REASON_LINES = 10
MARKER_DIR = Path(tempfile.gettempdir()) / "grok-ui-dirty"


def marker_path(cwd: Path) -> Path:
    key = hashlib.sha1(str(cwd).lower().encode("utf-8")).hexdigest()[:16]
    MARKER_DIR.mkdir(parents=True, exist_ok=True)
    return MARKER_DIR / f"{key}.json"


def read_marker(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def write_marker(path: Path, data: dict) -> None:
    try:
        path.write_text(json.dumps(data), encoding="utf-8")
    except OSError:
        pass


def run(cmd: list[str], cwd: Path) -> tuple[int, str, str]:
    try:
        p = subprocess.run(
            cmd, cwd=str(cwd), capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=60,
        )
        return p.returncode, p.stdout, p.stderr
    except Exception as exc:  # fail open
        return 1, "", str(exc)


def _ui(path: Path) -> bool:
    return path.suffix.lower() in UI_EXT and path.is_file()


def changed_files(cwd: Path, staged: bool) -> list[Path]:
    if staged:
        rc, out, _ = run(["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"], cwd)
        if rc != 0:
            return []
        return [cwd / p.strip() for p in out.splitlines() if p.strip() and _ui(cwd / p.strip())]

    rc, out, _ = run(["git", "status", "--porcelain"], cwd)
    if rc == 0:
        files = []
        for line in out.splitlines():
            if len(line) < 4:
                continue
            p = line[3:].strip()
            if " -> " in p:
                p = p.split(" -> ", 1)[1]
            p = p.strip().strip('"')
            f = cwd / p
            if p and _ui(f):
                files.append(f)
        return files[:MAX_FILES]

    # No git: catch greenfield files written in this session window.
    out_files = []
    skip = {"node_modules", ".git", "dist", "build", ".next", ".nuxt", ".svelte-kit", "coverage", "vendor"}
    now = time.time()
    for root, dirs, names in os.walk(cwd):
        dirs[:] = [d for d in dirs if d not in skip and not d.startswith(".")]
        for name in names:
            f = Path(root, name)
            if f.suffix.lower() not in UI_EXT:
                continue
            try:
                if now - f.stat().st_mtime < 7200:
                    out_files.append(f)
            except OSError:
                pass
        if len(out_files) >= MAX_FILES:
            break
    return out_files[:MAX_FILES]


def detect(files: list[Path], cwd: Path) -> list[dict]:
    if not DETECTOR.exists():
        return []
    findings: list[dict] = []
    for f in files[:MAX_FILES]:
        rc, out, _ = run([str(DETECTOR), "detect", "--json", str(f)], cwd)
        if not out.strip():
            continue
        try:
            data = json.loads(out)
        except json.JSONDecodeError:
            continue
        if isinstance(data, list):
            findings.extend(data)
    return findings


def reason(findings: list[dict]) -> str:
    lines = []
    seen = set()
    for f in findings:
        key = (f.get("file"), f.get("antipattern"), f.get("snippet"))
        if key in seen:
            continue
        seen.add(key)
        name = Path(str(f.get("file", "?"))).name
        lines.append(f"- {name}: {f.get('name') or f.get('antipattern')} ({f.get('snippet', '')})")
        if len(lines) >= MAX_REASON_LINES:
            break
    total = len(findings)
    head = f"Anti-slop gate: the Impeccable detector found {total} issue(s). Fix them before declaring done."
    tail = "If a finding is intentional, add a justified waiver in .impeccable/config.json (see impeccable.style/docs/detector)."
    return "\n".join([head, *lines, tail])


def main() -> int:
    staged = "--staged" in sys.argv
    payload = {}
    if not staged and not sys.stdin.isatty():
        try:
            payload = json.loads(sys.stdin.read() or "{}")
        except json.JSONDecodeError:
            payload = {}

    cwd = Path(payload.get("cwd") or payload.get("workspaceRoot") or os.getcwd())
    state_path = marker_path(cwd)

    # The Impeccable PostToolUse wrapper marks UI edits. If there has been no
    # UI edit since the last clean anti-slop scan, this Stop is a non-UI turn:
    # skip the expensive detector pass (it used to scan every recent UI file
    # in the workspace on every turn, ~50s in a design folder).
    if not staged:
        state = read_marker(state_path)
        if float(state.get("lastEdit") or 0) <= float(state.get("antislopScan") or 0):
            print(json.dumps({"continue": True}))
            return 0

    files = changed_files(cwd, staged)
    findings = detect(files, cwd) if files else []

    if not staged and not findings:
        state = read_marker(state_path)
        state["antislopScan"] = time.time()
        write_marker(state_path, state)

    if staged:
        if findings:
            print(reason(findings), file=sys.stderr)
            return 2
        return 0

    if findings:
        print(json.dumps({"decision": "block", "reason": reason(findings)}))
    else:
        print(json.dumps({"continue": True}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
