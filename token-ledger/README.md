# Grok token-ledger + auto-tuner

Automatic token-efficiency machinery for Grok Build on DeepSeek seats.
Two background daemons, zero oversight required after install.

## What it does

| Piece | File | Job |
|-------|------|-----|
| Ledger | `ledger.py` | Tails `~/.grok/logs/unified.jsonl`, appends one row per inference to `usage.jsonl` (prompt/cached/miss/completion/reasoning tokens + est. $), aggregates `sessions/*/signals.json` into `session_stats.jsonl`, refreshes `report.md` every 15 min. |
| Auto-tuner | `tuner.py` | Every 15 min, edits `~/.grok/config.toml` within hard bounds: `context_window` for **every `[model.*]` seat** that declares one (four seats since 2026-09-10), raised only, 128K–512K, 64K steps, one change/seat/24h; `default_reasoning_effort = "low"` when reasoning burn is >20% of output; disables the optional `paper` MCP server after repeated handshake failures. |
| Launcher | `start.ps1` | Starts both daemons detached (idempotent). |
| Register | `register-startup.ps1` | Scheduled task `GrokLedgerWatchdog`, every 15 minutes, launched through `run-hidden.vbs` so no console window flashes. Retires the old logon task if it is still registered. |
| Unregister | `unregister-startup.ps1` | Removes the task, stops daemons. Keeps data files. |
| Report | `report.ps1` | Regenerate `report.md` on demand. |

## Pricing used (deepseek-v4-flash, per 1M tokens)

- Input cache hit: $0.0028
- Input cache miss: $0.14
- Output (completion + reasoning): $0.28

## Safety

- The tuner never touches values pinned in `overrides.toml`.
- A timestamped `config.toml.bak-*` is written before the first automatic edit.
- Every automatic change is appended to `changes.log` (key, old → new, reason).
- `tuner.py --dry-run` prints what it would change without editing.
- Bounds: context window never below 128K or above 512K; reasoning effort is
  only ever lowered, never raised.

## Manual use

```powershell
# one-shot scan + report
python -u "$HOME\.grok\token-ledger\ledger.py" --once

# preview tuner actions
python -u "$HOME\.grok\token-ledger\tuner.py" --dry-run

# full report
powershell -ExecutionPolicy Bypass -File "$HOME\.grok\token-ledger\report.ps1"
```

## Tuning logic

- **Raise window** when the average peak context of the last day's sessions
  exceeds 80% of the declared window (compaction would otherwise hit quality),
  or when a session compacts 3+ times in a day.
- The window is **never lowered.** `context_window` is the auto-compaction
  trigger, not a cap on what gets sent, so lowering it saves no tokens — it only
  makes compaction fire sooner. (The lower-at-40% rule ran until 2026-09-10,
  when it had oscillated every seat 262144 → 196608 → 262144.)
- Applies to every seat that declares a `context_window` in `config.toml` —
  switch seats freely; none of them can run unbounded.
- Changes take effect on the next session (config is read at launch).
