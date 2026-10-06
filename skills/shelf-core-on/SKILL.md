---
name: shelf-core-on
description: Enable the core skill pack (the 16 baseline skills) from the shelf. Slash /shelf-core-on only.
argument-hint: ""
user-invocable: true
disable-model-invocation: true
metadata:
  short-description: "Enable core skill shelf"
---

# Enable core skill shelf

1. Run:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\grok-skill-shelf\shelf.ps1" enable core
```

2. Tell the user: the core pack is linked (route, delegate, web-search, capture-lesson, handoff, pull-handoff, code-review, diagnosing-bugs, tdd, codebase-design, domain-modeling, find-skills, here-now, resolving-merge-conflicts, wizard, writing-for-agents). Wait a few seconds; use `/` or name a skill. **Usually no new session needed.** Fallback: new session if not visible.
3. If the user wants the optional packs too, `/shelf-matt-on`, `/shelf-design-on`, `/shelf-video-on`, `/shelf-extras-on`, `/shelf-firecrawl-on`.
