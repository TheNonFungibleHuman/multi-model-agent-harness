---
name: shelf-video-on
description: Enable the video/animation skill pack from the shelf (hyperframes, motion, captions, etc.). Slash /shelf-video-on only.
argument-hint: ""
user-invocable: true
disable-model-invocation: true
metadata:
  short-description: "Enable video/animation skill shelf"
---

# Enable video/animation skill shelf

1. Run:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\grok-skill-shelf\shelf.ps1" enable video
```

2. Tell the user: video pack is linked (hyperframes, motion-doctrine, captions, etc.). Wait a few seconds, then type `/` or ask to use the video skills. **Usually no new session needed** (skills reload when files change). If the agent still can’t see them, start a new session.

3. To turn them back off: `/shelf-off` or `shelf.ps1 disable video`.
