#!/usr/bin/env python3
"""Scope the Impeccable design hooks to UI work.

PostToolUse: run the Impeccable warm scan only when the edited file is a UI
file. Non-UI edits exit immediately (this is the common case and the old hook
ran the scanner after every Write/Edit, which made every turn feel slow).

Stop: run the Impeccable deep pass only when a UI file has been edited since
the last successful scan. A small per-workspace marker records the last edit
and last clean scan; non-UI turns skip the detector entirely.

The hard anti-slop gate is separate (anti-slop-stop.py) and still scans files
changed in git, so this wrapper is about latency, not about weakening the gate.
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
DETECTOR = HOME / "grok-skill-shelf" / "design" / "impeccable" / "scripts" / "bin" / "windows-x64" / "impeccable.exe"
UI_EXT = {
    ".html", ".htm", ".css", ".scss", ".sass", ".less",
    ".tsx", ".jsx", ".vue", ".svelte", ".astro", ".php", ".mdx",
}
MARKER_DIR = Path(tempfile.gettempdir()) / "grok-ui-dirty"
TIMEOUT = 45


def _payload() -> tuple[dict, str]:
    raw = ""
    if not sys.stdin.isatty():
        raw = sys.stdin.read()
    try:
        return (json.loads(raw) if raw.strip() else {}), raw
    except json.JSONDecodeError:
        return {}, raw


def _cwd(payload: dict) -> Path:
    value = payload.get("cwd") or payload.get("workspaceRoot") or payload.get("projectRoot") or os.getcwd()
    try:
        return Path(value).resolve()
    except OSError:
        return Path.cwd()


def _marker(cwd: Path) -> Path:
    key = hashlib.sha1(str(cwd).lower().encode("utf-8")).hexdigest()[:16]
    MARKER_DIR.mkdir(parents=True, exist_ok=True)
    return MARKER_DIR / f"{key}.json"


def _read_marker(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def _write_marker(path: Path, data: dict) -> None:
    try:
        path.write_text(json.dumps(data), encoding="utf-8")
    except OSError:
        pass


def _edited_path(payload: dict) -> str:
    tool_input = payload.get("tool_input") or payload.get("toolInput") or {}
    if not isinstance(tool_input, dict):
        return ""
    for key in ("file_path", "filePath", "path", "target_file", "targetFile"):
        value = tool_input.get(key)
        if isinstance(value, str) and value.strip():
            return value
    return ""


def _run_detector(payload_text: str, cwd: Path) -> int:
    if not DETECTOR.exists():
        return 0
    try:
        p = subprocess.run(
            [str(DETECTOR), "hook"],
            input=payload_text,
            cwd=str(cwd),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=TIMEOUT,
        )
    except Exception:
        return 0  # fail open; the hard gate is separate
    if p.stdout:
        sys.stdout.write(p.stdout)
    if p.stderr:
        sys.stderr.write(p.stderr)
    return p.returncode


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    payload, raw = _payload()
    cwd = _cwd(payload)
    marker_path = _marker(cwd)

    if mode == "--post":
        edited = _edited_path(payload)
        if not edited:
            return 0
        if Path(edited).suffix.lower() not in UI_EXT:
            return 0
        state = _read_marker(marker_path)
        state["lastEdit"] = time.time()
        _write_marker(marker_path, state)
        return _run_detector(raw, cwd)

    if mode == "--stop":
        state = _read_marker(marker_path)
        last_edit = float(state.get("lastEdit") or 0)
        last_scan = float(state.get("lastScan") or 0)
        if last_edit <= last_scan:
            return 0  # no UI edit since the last clean scan
        rc = _run_detector(raw, cwd)
        blocked = rc != 0
        if not blocked:
            state["lastScan"] = time.time()
            _write_marker(marker_path, state)
        return rc

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
