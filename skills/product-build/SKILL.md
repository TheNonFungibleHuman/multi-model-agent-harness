---
name: product-build
description: >
  End-to-end product build conductor. Use when the user asks to build, ship or
  scaffold an app, product, MVP, feature, or hackathon project; says "build me",
  "make an app", "ship this", or wants a design-to-code build. Runs grill ->
  spec -> design gate -> plan on pro -> implement on flash -> verify -> review
  -> handoff, with the Impeccable detector as a hard anti-slop gate. Do not use
  for one-line fixes or trivial edits.
user-invocable: true
---

# Product build (conductor)

You own the pipeline. Do not wait to be told to delegate, to use a skill, or to
route a model; decide and proceed. Ask the user only product questions, never
permission for each step.

## 0. Classify

If the request is a new surface, feature, app, or MVP: run this pipeline. If it
is a one-line fix or a question, skip it and use the normal workflow.

## 1. Grill (one round, max 8 questions)

Ask only what changes the build:

1. Who is it for, and what do they do with it?
2. What are the 3 must-haves, in order?
3. What is explicitly out of scope?
4. Stack/runtime/deploy constraints?
5. Existing brand, assets, references, screenshots?
6. Definition of done (the exact demo behaviour + tests)?
7. Data/auth/payments/integrations?
8. Deadline or budget constraint?

If the user says "just build", proceed with an **Assumptions** list and say so.
Do not ask a second round of questions.

## 2. Spec and docs

Write at the repo root:

- `SPEC.md` — goal, users, must-haves, non-goals, acceptance checks.
- `DESIGN.md` — after the design gate (step 3).
- `AGENTS.md` — repo conventions and run/test commands.
- ADRs only for irreversible decisions.

Use the library when useful: `to-spec`, `to-tickets`, `domain-modeling`,
`grill-with-docs`. Search with the `skill-router`; load at most 3 skills.

## 3. Design gate (no UI code before this)

**Ask for references first.** Ask: “Do you have references — URLs, screenshots,
notes — or should I pull from Inspo?” Pass any with `-References`; if none, the
lane uses Inspo (free, MIT). Use `-NoInspo` only if they want no outside
inspiration. Steal like an artist: synthesize 2–3 sources; never copy a layout
1:1, copy, logos, or brand assets.

1. Produce **2–3 genuinely different directions** on the **pen.dev canvas**
   through the design lane:
   ```powershell
   powershell -File "$env:USERPROFILE\.grok\skills\skill-router\scripts\design-lane.ps1" `
     -Brief "<direction brief>" -Cwd . -Out .\design\directions\<name>
   ```
   No HTML/CSS mockups and no review server. The lane exports `preview.png`.
2. **AI review first:** check each direction against the canvas checklist in
   `rules/02-design-gate.md` (hierarchy, type, palette, contrast, spacing, one
   CTA, banned tells). Fix or reject in the canvas before showing the user.
3. The user picks in Pencil (or you pick only if they delegated).
4. Write `DESIGN.md`: palette, type scale, spacing, components, motion, chosen
   frame.
5. **Choose the component library after the pick**, from the stack and the job:
   React/Next → shadcn/ui + Radix + Tailwind; Vue → Nuxt UI; Svelte → Skeleton;
   Angular → Spartan/NG-ZORRO; marketing-only → none unless reused. One library,
   no component MCP, no full kit dump. Record the choice and why in `AGENTS.md`
   or `DESIGN.md`.
6. Then — and only then — implement.

Surface → skill (via `skill-router`):

- Product UI / app shell / dashboard → **Impeccable** (`shape` → `craft`) +
  Jakub `better-ui` / `better-typography` / `better-layout`.
- Component states → Jakub `break` / `state-machine`.
- Motion → `emil-design-eng`.
- Landing / marketing / portfolio → **Taste v2** (after direction approval).
- Copy → Jakub `better-writing`; color system → `better-colors`.
- Figma/design image → code → Jakub `build-design`.

One primary + one gate. No rival reviewers. No pack enabling.

## 4. Plan on pro

Spawn the `plan` subagent (config pins it to `deepseek-pro`) with `SPEC.md` and
`DESIGN.md`. Require:

- Goals / non-goals
- Ordered steps with files/areas and acceptance checks
- Risks and open questions
- The smallest vertical slice to build first

Then implement that slice on Flash. Do not plan the whole product on Flash.

## 5. Implement on Flash

- Main session or a `general-purpose` child on `deepseek-flash`; keep bulk work
  off the pro seat.
- Load 1–3 skills via `skill-router`; delegate heavy skill bodies to a child and
  take back a short summary.
- Follow `DESIGN.md`; write tests with the slice; run them.
- End each change with the evidence line: files changed + exact test command +
  result (or the blocker).

## 6. Verify (hard)

- `rules/01-verification.md` + `tdd`: symbol sweep, project env first,
  neighborhood sweep, evidence line.
- The design detector (Stop hook) blocks completion while changed UI files have
  findings. Fix them or add a justified waiver. Do not disable the gate.
- For the repo itself, install the pre-commit gate once:
  ```powershell
  powershell -File "$env:USERPROFILE\.grok\skills\skill-router\scripts\install-design-guard.ps1" -Repo .
  ```
  It scans staged UI files and blocks the commit on findings.
- Visual proof: screenshot desktop + mobile and compare with the chosen
  direction. No screenshot, no "done".

## 7. Review on pro

Spawn **one** reviewer (`general-purpose`, `model: deepseek-pro`) with
`code-review` or `diagnosing-bugs`. Give it the diff, the spec, and the design
contract. Fix blockers; re-run tests + detector.

## 8. Ship

Commit/PR with a clear message. Use `make-pr-easy-to-review` / `babysit` only
when the task is a PR. Update `SPEC.md` / `DESIGN.md` / `AGENTS.md` with what
actually shipped.

## 9. Handoff (automatic trigger)

At ~70% context, or after **two failed attempts** on the same problem:

1. Write `%USERPROFILE%\.grok\handoffs\<slug>-YYYYMMDD-HHMM.md` with Goal, Done,
   Open, Key paths, Commands/state, Risks, Do-not-redo.
2. Tell the user to run `/new`, then `/pull-handoff <file>` — no exit needed.
   A new process can use `start-grok.ps1 -ResumeHandoff` instead.
3. Do not keep thrashing a bloated session.

## 10. Retro

Run `capture-lesson` for any real failure (symptom, cause, rule, scope,
anti-pattern). Update `AGENTS.md` with anything the next agent must know.

## Cost and model rules

| Work | Seat |
|---|---|
| Main implementation, tests, refactors | `deepseek-flash-high` (default) |
| Planning, architecture, hard bugs, review | `deepseek-pro` (spawn; never daily driver) |
| Cheap bulk / parallel explores | `deepseek-flash` |
| Overflow bulk | `glm-flash` |

- Keep the main context lean: subagent summaries, not transcripts.
- Handoff before compaction; compaction costs tokens and loses fidelity.
- Report cost when the ledger has it; don't guess.

## Anti-slop hard rules

- No UI output without a chosen design artifact and `DESIGN.md`.
- The detector is a gate, not advice. Findings block "done".
- One reviewer per pass; one primary design skill; no duplicate variants.
- If a skill is user-only (`disable-model-invocation: true`), ask the user to
  invoke it or use the flipped library copy.
