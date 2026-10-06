---
name: shelf-off
description: Disable all optional skill shelf packs (design, Matt, video, extras, firecrawl), leaving the core pack on. Slash /shelf-off only.
argument-hint: ""
user-invocable: true
disable-model-invocation: true
metadata:
  short-description: "Disable skill shelf packs"
---

# Disable skill shelf packs

1. Run:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\grok-skill-shelf\shelf.ps1" disable all
```

2. Tell the user packs are unlinked (files remain on the shelf). The core pack is untouched — `disable all` skips it by design; turning core off takes `shelf.ps1 disable core`. Token list should shrink on the next model turn; if not, new session. Re-enable with `/shelf-core-on`, `/shelf-design-on`, `/shelf-matt-on`, `/shelf-video-on`, `/shelf-extras-on`, or `/shelf-firecrawl-on`.
