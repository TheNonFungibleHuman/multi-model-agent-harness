---
name: handoff
description: >
  Write a compact handoff document so another Grok session (or agent) can
  continue this work. Use when the user says /handoff, wants to switch sessions,
  open a parallel agent, or move context without pasting the whole chat.
argument-hint: "What will the next session focus on?"
user-invocable: true
disable-model-invocation: true
---

# Write handoff

Create a **short** handoff for a fresh agent. Prefer disk over chat paste.

## Where to save

Primary (stable, cross-session):

```text
%USERPROFILE%\.grok\handoffs\<slug>-YYYYMMDD-HHMM.md
```

Also acceptable: OS temp dir if the user asked for ephemeral only.

Slug from the focus args or a 2–4 word summary of the goal (kebab-case).

## Contents (keep tight)

```markdown
# Handoff: <title>

- **Date:** …
- **CWD:** …
- **Suggested model:** deepseek-flash | deepseek-flash-high | grok-4.6
- **Focus for next session:** <from user args if any>

## Goal
…

## Done
- …

## Open
- …

## Key paths
- `path` — why

## Commands / state
- branch, tests, servers (if relevant)

## Risks / constraints
- …

## Suggested skills
- …

## Do not re-do
- …
```

## Rules

1. Do **not** duplicate full specs/plans/diffs already on disk — link paths.
2. Redact secrets (API keys, tokens, passwords, PII).
3. Prefer bullets over essays. Target **under ~80 lines**.
4. If the user passed arguments, treat them as the next session’s focus and tailor the doc.
5. After writing, print the **full path** and tell them to run `/pull-handoff` (or `/pull-handoff <filename>`) in the other session.
6. Mention `/dashboard` (`Ctrl+\`) if they want parallel agents in the same pager.
