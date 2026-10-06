---
name: shelf-extras-on
description: Enable the extras skill pack from the shelf (research, qa, obsidian-vault, design extras). Slash /shelf-extras-on only.
argument-hint: ""
user-invocable: true
disable-model-invocation: true
metadata:
  short-description: "Enable extras skill shelf"
---

# Enable extras skill shelf

1. Run:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\grok-skill-shelf\shelf.ps1" enable extras
```

2. Tell the user: extras pack is linked (research, qa, obsidian-vault, emil/apple design, etc.). Wait a few seconds, then type `/` or ask to use them. **Usually no new session needed.** Fallback: new session if not visible.

3. To turn them back off: `/shelf-off` or `shelf.ps1 disable extras`.
