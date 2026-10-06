---
name: mcp-design-status
description: Show whether Paper/Open Design MCP and design skills are on or off. Slash /mcp-design-status only.
argument-hint: ""
user-invocable: true
disable-model-invocation: true
metadata:
  short-description: "Design MCP on/off status"
---

# Design MCP status

1. Run exactly:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.grok\toggle-design-mcp.ps1" status
```

2. Report ON/OFF for **paper** and **open-design**, and whether design skills are in the catalog.

3. Remind: `/mcp-design-on` · `/mcp-design-off` · apply with `/mcps` then `r` (no restart for MCP); skill-catalog refresh is next session.
