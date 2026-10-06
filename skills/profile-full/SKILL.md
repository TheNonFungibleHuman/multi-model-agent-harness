---
name: profile-full
description: Switch Grok to the full config profile (design MCP on, broader skill catalog). Slash command /profile-full only.
argument-hint: ""
user-invocable: true
disable-model-invocation: true
metadata:
  short-description: "Switch to full skill profile"
---

# Switch to full profile

Apply the user's **full** Grok config (`~/.grok/config.full.toml` → `~/.grok/config.toml`).

## Steps (do all of them)

1. Run this exact PowerShell command with the shell tool:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.grok\switch-profile.ps1" full
```

2. If the script is missing, fall back to:

```powershell
Copy-Item "$env:USERPROFILE\.grok\config.full.toml" "$env:USERPROFILE\.grok\config.toml" -Force
```

3. Confirm the command printed `Active profile: FULL` (or that the copy succeeded).

4. Tell the user clearly:
   - Full profile is written to disk (**Paper + Open Design MCP ON**, broader skills).
   - Firecrawl/game packs stay disabled; Neon is not re-enabled.
   - **MCP applies now — no restart:** in the running Grok TUI run `/mcps` and press `r` to re-read `config.toml`. The design MCP toggle goes live immediately (or press `Space` on the server in `/mcps`).
   - **Skill catalog is next session:** the broader `[skills]` set is read at session start, so the skill LIST refresh still wants a new session. Skill files on disk hot-reload, but the config-driven catalog does not.
   - If you only care about the design MCP, you are done now — no restart needed. Otherwise restart to refresh the skill catalog.
   - To save tokens later: `/profile-lean` (or just `/mcp-design-off` if you only want MCP off).

5. Do not edit the profile template files unless the user asks.
