---
name: profile-status
description: Show whether the lean or full Grok config profile is active. Slash command /profile-status only.
argument-hint: ""
user-invocable: true
disable-model-invocation: true
metadata:
  short-description: "Show lean vs full profile"
---

# Show active Grok config profile

## Steps

1. Run:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.grok\switch-profile.ps1"
```

2. Report the result in plain language: **LEAN**, **FULL**, or **CUSTOM**.

3. Remind them:
   - Switch with `/profile-lean` (token-lean, design MCP off) or `/profile-full`
   - Design MCP only: `/mcp-design-on` · `/mcp-design-off` · `/mcp-design-status`
   - **Mid-session (no restart):** after switching, run `/mcps` and press `r` to reload MCP from `config.toml` — the design MCP toggle applies immediately. Only the skill-catalog trim needs a fresh session.
   - Optional check after restart: `grok inspect`
