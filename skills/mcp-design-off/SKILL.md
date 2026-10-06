---
name: mcp-design-off
description: Disable Paper + Open Design MCP and design skills for a leaner token baseline. Slash /mcp-design-off only.
argument-hint: ""
user-invocable: true
disable-model-invocation: true
metadata:
  short-description: "Disable design MCP (token-lean)"
---

# Disable design MCP (token-lean)

1. Run exactly:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.grok\toggle-design-mcp.ps1" off
```

2. Tell the user:
   - **Paper** and **Open Design** are disabled in `config.toml`.
   - **Apply now — no restart:** run `/mcps` and press `r` to re-read `config.toml`. The design MCP drop is live immediately.
   - Design-related skills were disabled in config; the catalog refresh applies at the next session start (skill files on disk still hot-reload).
   - Re-enable later with `/mcp-design-on`.
