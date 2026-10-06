---
name: shelf-matt-on
description: Enable Matt Pocock engineering skill pack from the shelf. Slash /shelf-matt-on only.
argument-hint: ""
user-invocable: true
disable-model-invocation: true
metadata:
  short-description: "Enable Matt Pocock skill shelf"
---

# Enable Matt Pocock skill shelf

1. Run:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\grok-skill-shelf\shelf.ps1" enable matt
```

2. Tell the user: Matt pack is linked. Wait a few seconds; use `/` or name skills (grill-me, to-spec, implement, etc.). **Usually no new session needed.** Fallback: new session if not visible.
