#!/usr/bin/env python3
"""Stop hook: block "done" when code changed but the final message has no
test evidence.

Reads the session transcript, checks git for changed code files, and requires
an evidence phrase (test command / pass / fail / blocker). Docs-only changes
are exempt.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

CODE_EXT = {
    ".py", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".vue", ".svelte",
    ".go", ".rs", ".java", ".cs", ".rb", ".php", ".sql", ".sh", ".ps1",
    ".c", ".cpp", ".h", ".hpp", ".kt", ".swift", ".dart", ".lua", ".ex", ".exs",
}
EVIDENCE = re.compile(
    r"(?i)\b(tests?|pytest|npm test|pnpm test|yarn test|bun test|cargo test|"
    r"go test|dotnet test|mvn test|gradle test|unittest|vitest|jest|phpunit|"
    r"rspec|tox|nox|not run|blocked|no tests|tests? (pass|fail)|ran .*test)\b"
)


def session_dir(sid: str | None) -> Path | None:
    if not sid:
        return None
    root = Path.home() / ".grok" / "sessions"
    for p in root.glob(f"*/{sid}"):
        if p.is_dir():
            return p
    return None


def last_assistant(d: Path) -> str:
    f = d / "chat_history.jsonl"
    if not f.is_file():
        return ""
    last = ""
    for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            o = json.loads(line)
        except json.JSONDecodeError:
            continue
        if o.get("type") == "assistant" and isinstance(o.get("content"), str) and o["content"].strip():
            last = o["content"].strip()
    return last


def changed_code(cwd: Path) -> list[str]:
    try:
        p = subprocess.run(
            ["git", "status", "--porcelain"], cwd=str(cwd),
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=15,
        )
    except Exception:
        return []
    if p.returncode != 0:
        return []
    out = []
    for line in p.stdout.splitlines():
        if len(line) < 4:
            continue
        path = line[3:].strip()
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        path = path.strip().strip('"')
        if path and Path(path).suffix.lower() in CODE_EXT:
            out.append(path)
    return out


def main() -> int:
    payload = {}
    if not sys.stdin.isatty():
        try:
            payload = json.loads(sys.stdin.read() or "{}")
        except json.JSONDecodeError:
            payload = {}

    cwd = Path(payload.get("cwd") or os.getcwd())
    d = Path(payload["session_dir"]) if payload.get("session_dir") else session_dir(
        payload.get("sessionId") or payload.get("session_id")
    )
    if d is None:
        print(json.dumps({"continue": True}))
        return 0

    files = changed_code(cwd)
    if not files:
        print(json.dumps({"continue": True}))
        return 0

    last = last_assistant(d)
    if EVIDENCE.search(last):
        print(json.dumps({"continue": True}))
        return 0

    reason = (
        f"Evidence gate: {len(files)} code file(s) changed but the final message has no test evidence. "
        "Run the relevant tests in the project's own environment, then end with the evidence line: "
        "files changed + exact test command + result (or quote the exact blocker and say 'tests not run')."
    )
    print(json.dumps({"decision": "block", "reason": reason}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
