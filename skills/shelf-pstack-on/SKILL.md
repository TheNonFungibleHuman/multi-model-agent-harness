---
name: shelf-pstack-on
description: Enable the pstack (poteto-mode) skill pack from the shelf. Slash /shelf-pstack-on only.
argument-hint: ""
user-invocable: true
disable-model-invocation: true
metadata:
  short-description: "Enable pstack (poteto-mode) skill shelf"
---

# Enable pstack (poteto-mode) skill shelf

1. Run:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\grok-skill-shelf\shelf.ps1" enable pstack
```

2. Tell the user: pstack pack is linked (63 skills; the catalog grows while it is on). Then ask for **poteto-mode** by name — Grok Build has no routing hook, so name the skill when you want it. Model choices for pstack roles live in `%USERPROFILE%\grok-skill-shelf\pstack\pstack-models.md`. Turn it off with `/shelf-off` or `shelf.ps1 disable pstack`. Fallback: new session if skills are not visible.
