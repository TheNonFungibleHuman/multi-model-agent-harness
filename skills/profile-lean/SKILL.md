---
name: profile-lean
description: Switch Grok to the lean config profile (fewer skills, Neon off, lower base tokens). Slash command /profile-lean only.
argument-hint: ""
user-invocable: true
disable-model-invocation: true
metadata:
  short-description: "Switch to lean skill profile"
---

# Switch to lean profile

Apply the user's **lean** Grok config (`~/.grok/config.lean.toml` → `~/.grok/config.toml`).

## Steps (do all of them)

1. Run this exact PowerShell command with the shell tool (do not invent another path):

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.grok\switch-profile.ps1" lean
```

2. If the script is missing, fall back to:

```powershell
Copy-Item "$env:USERPROFILE\.grok\config.lean.toml" "$env:USERPROFILE\.grok\config.toml" -Force
```

3. Confirm the command printed `Active profile: LEAN` (or that the copy succeeded).

4. Tell the user clearly:
   - Lean profile is written to disk (**token-lean default**).
   - Design MCP (**Paper**, **Open Design**) is **OFF**; heavy skills are disabled.
   - **MCP applies now — no restart:** in the running Grok TUI run `/mcps` and press `r` to re-read `config.toml`. The design MCP toggle goes live immediately (or press `Space` on the server in `/mcps`).
   - **Skill catalog is next session:** the `[skills] disabled` trim is read at session start, so the skill LIST refresh still wants a new session. Skill files on disk hot-reload, but the disabled-list trim does not.
   - If you only care about the design MCP, you are done now — no restart needed. Otherwise restart to refresh the skill catalog.
   - For design work later: `/mcp-design-on` (apply now via `/mcps`+`r`). For kitchen-sink: `/profile-full`.

5. Do not edit `config.lean.toml` or `config.full.toml` unless the user asks. Do not enable Neon.
