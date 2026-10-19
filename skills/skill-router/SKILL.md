---
name: skill-router
description: >
  On-demand skill library and role router for this harness. Use before any
  non-trivial task that may need a specialized skill: product builds, design
  and UI work, debugging, review, planning, pstack, matt-pocock, video or
  firecrawl. Search the shelf, load only the 1-3 skills the task needs, and
  never bulk-enable packs. Also carries the design-stack policy: Impeccable
  for product UI, Taste v2 for marketing pages, Jakub's better-* for interface
  execution, emil-design-eng for motion, with Impeccable's detector as the
  gate and a mockup-first design gate before implementation.
user-invocable: true
---

# Skill router (on-demand library)

The shelf packs are **not linked** into `~/.grok/skills`; their descriptions are
not in the prompt. The shelf is a library, not a catalog. Search it, read only
what the task needs, then continue.

## Load a skill

```powershell
python "$env:USERPROFILE\.grok\skills\skill-router\scripts\skill-search.py" "<what you need>"
```

The script prints the best matches with `name`, `pack`, `path`, and a one-line
description. Then either:

- `read_file` the chosen `SKILL.md` (use `limit`/`offset` for long files), or
- spawn a subagent whose prompt says: *read `<path>` and execute it; return a
  short summary*. Prefer the subagent for skills with long bodies or heavy
  scripts: the body stays in the child's context and the parent stays lean.

**Rules**

1. Load **1–3 skills per task**, never a whole pack.
2. Do not run `shelf.ps1 enable` or `/shelf-*` to "make a skill visible"; read it
   from the shelf instead.
3. If a skill's frontmatter still says `disable-model-invocation: true`, it is
   user-only. Ask the user to invoke it, or use the library copy if it has been
   flipped to `false`.
4. After the task, do not re-read the skill; use the project files and the
   evidence line.

## Design stack (surface → skill)

| Surface | Primary | Supporting | Gate |
|---|---|---|---|
| Product UI, dashboards, app shell | **Impeccable** (`shape` → `craft` → `polish`) | Jakub `better-ui` + `better-typography`/`better-layout`; `emil-design-eng` for motion | Impeccable detector (hook) + screenshots |
| Component states / design-system stress | Jakub `break` + `state-machine` | `better-accessibility` | Detector |
| Design exploration / variants | Jakub `variant` *or* `prototype` | `better-ui` | User picks one |
| Copy / UX writing | Jakub `better-writing` | Impeccable `clarify` | — |
| Color system | Jakub `better-colors` | Impeccable tokens | Contrast check |
| Design image / Figma → UI | Jakub `build-design` | `DESIGN.md`, project tokens/components | Detector + screenshot |
| Landing / portfolio / marketing | **Taste v2** (`design-taste-frontend`) | Jakub `better-typography`/`better-writing` | Taste `inspect.mjs` + Impeccable detector |
| Pre-ship review | **One** of: Jakub `interface-review`, Impeccable `audit`/`critique` | — | Detector |
| Explain a web interaction | Jakub `explain-interface` | — | — |
| Motion / micro-interactions | `emil-design-eng` | Impeccable `animate` | Detector motion rules |

**Never** run Taste and Impeccable as rival reviewers on the same pass, and never
load both `variant` and `prototype`. One primary + one gate is the rule.

## Design gate (before UI code)

For any new UI or redesign, do not start implementation until:

**Ask for references first.** Ask: “Do you have references — URLs, screenshots,
notes — or should I pull from Inspo?” Pass any with `-References`; if none, the
lane uses Inspo (free, MIT). Use `-NoInspo` only if they want no outside
inspiration. Steal like an artist: synthesize 2–3 sources; never copy a layout
1:1, copy, logos, or brand assets.

1. **2–3 genuinely different directions** exist as **pen.dev frames** created
   through the design lane:
   ```powershell
   powershell -File "$env:USERPROFILE\.grok\skills\skill-router\scripts\design-lane.ps1" `
     -Brief "<direction brief>" -Cwd . -Out .\design\directions\<name>
   ```
   No HTML/CSS mockups and no review server. The lane starts a child session
   with pencil, designs on the canvas, and exports `preview.png`.
2. **AI review first.** Review every exported direction against the canvas
   checklist in `rules/02-design-gate.md` (hierarchy, type, palette, contrast,
   spacing, one CTA, banned tells). Reject or fix in the canvas; only clean
   directions go to the user.
3. **The user picks in Pencil.** Show the canvas and the PNGs; they pick a
   direction. Do not build a comparison page.
4. `DESIGN.md` records the chosen frame's palette, type scale, spacing,
   component inventory, and motion rules. Implementation follows it.

The Impeccable Stop hook enforces the detector on **implemented UI code**, not
on the `.pen` canvas. The canvas review is vision + `Get`; the user's approval is
the gate.

## Detector and hooks (already installed)

```powershell
& "$env:USERPROFILE\grok-skill-shelf\design\impeccable\scripts\impeccable.cmd" detect <path-or-url>
```

- User hook: `~/.grok/hooks/impeccable.json` — PostToolUse (Edit/Write/MultiEdit)
  warms the scan; the Stop pass surfaces findings to the model.
- A second Stop entry runs `scripts/anti-slop-stop.py`: it scans changed UI
  files and **blocks completion** while findings exist. Verified: 5 findings →
  `decision: block`; clean → `continue: true`.
- Pre-commit guard for product repos:
  ```powershell
  powershell -File "$env:USERPROFILE\.grok\skills\skill-router\scripts\install-design-guard.ps1" -Repo <path>
  ```
- The detector is deterministic and needs no API key. Fix findings or record a
  justified waiver in `.impeccable/config.json`.
- Taste v2 needs Node 22+ and Chrome/Edge for `scripts/inspect.mjs`; a full
  marketing-page run is heavy (30–45 min, hundreds of thousands of tokens). Use
  it for impression pages, not app screens.

## Examples

- *"Build me X for a hackathon"* → search; load `grill-me` + `to-spec`; design
  gate with `high-end-visual-design` + `emil-design-eng`; plan on pro; implement
  on flash; `tdd`/`better-*` as needed; detector; handoff.
- *"Review this bug"* → the always-on `code-review`/`diagnosing-bugs` first; load
  `blast-radius` or Jakub `interface-review` only if the change is risky/UI.
- *"Make a video"* → search `video`; load 2–3 relevant skills, not the 31-skill pack.
- *"This page looks AI-made"* → Taste v2 (`design-taste-frontend`) + Impeccable
  detector; no other style pack.

## Maintenance

- Shelf path: `~/grok-skill-shelf/<pack>/<skill>/SKILL.md`.
- Versions in use (2026-10-18): Impeccable 4.6.0, Taste 2.0.0, Jakub 14 skills.
- If a skill misleads or fails, record a `capture-lesson` entry with the pack and
  case, and prefer the better-fitting skill next time.
