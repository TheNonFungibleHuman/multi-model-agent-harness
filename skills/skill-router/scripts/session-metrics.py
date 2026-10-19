#!/usr/bin/env python3
"""SessionEnd hook: append one trajectory record per primary session.

Records turns, tool calls, context peak, tokens, duration, and edit volume to
~/.grok/metrics/sessions.jsonl. No model call, no API cost.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

OUT = Path(os.environ.get("HARNESS_METRICS_OUT") or (Path.home() / ".grok" / "metrics" / "sessions.jsonl"))


def find_session(payload: dict) -> Path | None:
    if payload.get("session_dir"):
        p = Path(payload["session_dir"])
        return p if p.is_dir() else None
    sid = payload.get("sessionId") or payload.get("session_id")
    if not sid:
        return None
    root = Path.home() / ".grok" / "sessions"
    for p in root.glob(f"*/{sid}"):
        if p.is_dir():
            return p
    return None


def load(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return {}


def main() -> int:
    payload = {}
    if not sys.stdin.isatty():
        try:
            payload = json.loads(sys.stdin.read() or "{}")
        except json.JSONDecodeError:
            payload = {}

    # Subagent sessions are logged by their type, not as product sessions.
    if payload.get("subagentType") or payload.get("subagent_type"):
        return 0

    d = find_session(payload)
    if d is None:
        return 0

    summary = load(d / "summary.json")
    kind = summary.get("session_kind")
    if kind in ("subagent", "headless"):
        return 0

    sig = load(d / "signals.json")
    rec = {
        "ts": __import__("datetime").datetime.now().isoformat(timespec="seconds"),
        "session": d.name,
        "cwd": str(Path(payload.get("cwd") or os.getcwd())),
        "model": summary.get("current_model_id") or sig.get("primaryModelId"),
        "agent": summary.get("agent_name"),
        "title": summary.get("generated_title") or summary.get("session_summary"),
        "turns": sig.get("turnCount"),
        "user_messages": sig.get("userMessageCount"),
        "assistant_messages": sig.get("assistantMessageCount"),
        "tool_calls": sig.get("toolCallCount"),
        "tools": sig.get("toolsUsed"),
        "errors": sig.get("errorCount"),
        "tool_failures": sig.get("toolFailureCount"),
        "compactions": sig.get("compactionCount"),
        "context_pct": sig.get("contextWindowUsage"),
        "context_tokens": sig.get("contextTokensUsed"),
        "window": sig.get("contextWindowTokens"),
        "duration_s": sig.get("sessionDurationSeconds"),
        "lines_added": sig.get("agentLinesAdded"),
        "lines_removed": sig.get("agentLinesRemoved"),
        "files_touched": sig.get("agentFilesTouched"),
        "reason": payload.get("reason") or payload.get("sessionEndReason"),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("a", encoding="utf-8") as f:
        f.write(json.dumps(rec) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
