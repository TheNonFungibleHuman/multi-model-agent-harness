---
name: shelf-design-on
description: Enable design/impeccable skill pack from the shelf (junctions into ~/.grok/skills). Slash /shelf-design-on only.
argument-hint: ""
user-invocable: true
disable-model-invocation: true
metadata:
  short-description: "Enable design skill shelf"
---

# Enable design skill shelf

1. Run:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\grok-skill-shelf\shelf.ps1" enable design
```

2. Tell the user: design pack is linked. Wait a few seconds, then type `/` or ask to use impeccable / design skills. **Usually no new session needed** (skills reload when files change). If the agent still can’t see them, start a new session.
