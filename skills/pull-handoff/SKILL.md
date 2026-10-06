---
name: pull-handoff
description: >
  Load the latest (or named) handoff brief from ~/.grok/handoffs into this
  session so work can continue. Use when the user says /pull-handoff, "continue
  from handoff", or "pick up the other session".
argument-hint: "[optional-handoff-filename]"
user-invocable: true
---

# Pull handoff into this session

Load a compact handoff so this agent can continue without replaying the full prior transcript.

## Steps

1. Resolve the handoffs directory:

```powershell
$dir = Join-Path $env:USERPROFILE ".grok\handoffs"
```

2. Choose the file:
   - If the user passed an argument, treat it as a filename or substring (e.g. `auth-fix.md`).
   - Else pick the **most recently modified** `*.md` in that directory (ignore `README.md`).

3. Read the full handoff file with the file tool.

4. Restate in ≤12 bullets:
   - Goal
   - Done so far
   - Open work
   - Key paths
   - Risks / constraints
   - Suggested model seat (Flash / Grok / Gemini)
   - Suggested skills

5. Ask **one** clarifying question only if the handoff is ambiguous; otherwise continue the open work.

6. Do **not** dump the entire prior chat. Trust the handoff + repo state (`git status`, key files).

If the directory is empty, tell the user to run `/handoff` in the source session first.
