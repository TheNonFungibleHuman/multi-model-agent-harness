---
name: shelf-status
description: Show whether core / design / Matt / video / extras / firecrawl skill shelf packs are enabled. Slash /shelf-status only.
argument-hint: ""
user-invocable: true
disable-model-invocation: true
metadata:
  short-description: "Skill shelf status"
---

# Skill shelf status

Run:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\grok-skill-shelf\shelf.ps1" status
```

Report ON/OFF for **core**, **design**, **matt-pocock**, **video**, **extras**, and **firecrawl**. Remind: enable core with `/shelf-core-on`; the optional packs with `/shelf-design-on`, `/shelf-matt-on`, `/shelf-video-on`, `/shelf-extras-on`, or `/shelf-firecrawl-on`; disable the optional packs with `/shelf-off`. Mention that `shelf.ps1 disable all` leaves the core pack alone — turning core off takes `shelf.ps1 disable core`.
