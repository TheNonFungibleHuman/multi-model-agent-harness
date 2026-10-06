---
name: shelf-firecrawl-on
description: Enable the firecrawl skill pack (config-shelved via [skills] disabled). Slash /shelf-firecrawl-on only.
argument-hint: ""
user-invocable: true
disable-model-invocation: true
metadata:
  short-description: "Enable firecrawl skill shelf"
---

# Enable firecrawl skill shelf

firecrawl skills are not installed into a Grok scan root, so they are shelved via the
`[skills] disabled` list in `~/.grok/config.toml`. Enabling removes those entries.

1. Run:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\grok-skill-shelf\shelf.ps1" enable firecrawl
```

2. Tell the user: firecrawl entries removed from `[skills] disabled`. A backup is saved at
   `config.toml.shelfbak`. Note: for firecrawl skills to actually load, they must first be
   installed into a Grok scan root (e.g. `~/.grok/skills`); today they live only under
   `~/.codeium/windsurf/skills`, which Grok does not scan.

3. To re-shelf: `/shelf-off` or `shelf.ps1 disable firecrawl`.
