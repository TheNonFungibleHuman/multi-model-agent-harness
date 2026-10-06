---
name: mcp-design-on
description: Enable Paper + Open Design MCP (and design skills) for UI work. Slash /mcp-design-on only.
argument-hint: ""
user-invocable: true
disable-model-invocation: true
metadata:
  short-description: "Enable design MCP servers"
---

# Enable design MCP

1. Run exactly:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.grok\toggle-design-mcp.ps1" on
```

2. Tell the user:
   - **Paper** and **Open Design** MCP are now enabled in `config.toml`.
   - **Apply now — no restart:** run `/mcps` in the running Grok TUI and press `r` to re-read `config.toml` (or press `Space` on the server in `/mcps`). The design MCP goes live immediately.
   - Design-related skills were re-enabled in config; the skill-catalog refresh applies at the next session start.
   - **gemini-docs** stays off (flaky; not required for design).
   - Optional skill pack: `/shelf-design-on` if they use the design shelf.

3. Do not claim MCP is live in *this* chat until they press `r` in `/mcps`.
