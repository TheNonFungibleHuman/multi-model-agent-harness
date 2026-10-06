---
name: capture-lesson
description: >
  Capture a durable lesson from a bug, failed approach, or correction so future
  sessions improve. Use after fixing a painful bug, when the user says "remember
  this", "don't do that again", or /capture-lesson.
argument-hint: "[optional short title]"
user-invocable: true
---

# Capture lesson (harness memory)

Turn a mistake into a short, reusable rule. This is how the harness "gets better" without model fine-tuning.

## Steps

1. Infer from the conversation (or user args):
   - **Symptom** — what went wrong
   - **Root cause** — why
   - **Rule** — what to do differently next time (imperative, 1–3 sentences)
   - **Scope** — language/repo/tool if specific
   - **Anti-pattern** — what not to repeat

2. Append one entry to:

`$env:USERPROFILE\.grok\lessons\LESSONS.md`

Use this template:

```markdown
## YYYY-MM-DD — <short title>

- **Symptom:** …
- **Cause:** …
- **Rule:** …
- **Scope:** …
- **Anti-pattern:** …
```

3. If the lesson is project-specific and the user is in a git repo, also offer to add a one-liner under that repo’s `AGENTS.md` (only if they agree).

4. Optionally suggest `/remember` for a one-line cross-session memory if Grok memory is enabled.

5. Confirm the file path and the rule in one sentence. Do not lecture.

## Quality bar

- Actionable for a future agent with no chat history
- No secrets, tokens, or personal data
- Prefer concrete ("always run X before Y") over vague ("be careful")
