# Design gate (home rules — apply to every UI build)

**Ask for references before the canvas.** Ask: “Do you have references — URLs,
screenshots, notes — or should I pull from Inspo?” If they provide any, pass
them with `-References`; if they have none, the lane uses Inspo (free, MIT,
inspomcp.dev). If they explicitly want no outside inspiration, use `-NoInspo`.
Steal like an artist: synthesize 2–3 sources into a new direction; never copy a
layout 1:1, never reuse copy, logos, or brand assets, and never blindly copy a
palette. If a reference conflicts with the banned tells, the banned tells win.

1. **Canvas first, Pencil only.** Produce **2–3 genuinely different directions**
   on the pen.dev canvas through `design-lane.ps1`. No HTML/CSS mockups, no
   local review server, no generated review page. The user sees the designs in
   Pencil.
2. **Each direction is a real frame set.** Desktop and mobile frames where the
   surface is responsive, real copy (no lorem, no invented metrics), and a
   `preview.png` exported by the lane. Name the frames clearly.
3. **AI review before the user sees it.** Review every direction against this
   checklist and fix or reject it in the canvas first:
   - one clear idea and one primary action; no competing solid CTAs
   - hierarchy: the eye lands on the headline, then the proof, then the action
   - type: display vs body contrast, no Inter/Roboto/Arial/Fraunces as display
   - palette: one decisive accent, no purple gradient wash, no warm cream page
     wash, 4.5:1 body contrast, visible focus states
   - spacing: deliberate rhythm, no clipping, overflow, collisions, or orphan
     lines; 44px touch targets
   - content: specific, honest, no filler, no fake product UI, no emoji icons,
     no left-bar callout cards, no invented testimonials, quotes, metrics, or
     customer names
   - originality: not a 1:1 copy of a reference; sources synthesized, no
     borrowed logos, brand assets, or copy
   - motion: one idea, reduced-motion safe
   Only directions that pass go to the user.
4. **The user picks on the canvas.** No implementation, no DESIGN.md, and no
   code before the pick.
5. **`DESIGN.md` is the contract.** Palette, type scale, spacing, components,
   motion, and the chosen frame's name. Implementation follows it; deviations
   are recorded.
6. **One primary design skill + one gate.** Product UI → Impeccable + Jakub;
   marketing/landing → Taste v2; motion → emil-design-eng. Never two rival
   reviewers on the same pass; never enable a whole pack.
7. **The Impeccable detector is the gate for implemented UI code.** It does not
   scan the `.pen` canvas. The canvas is reviewed by vision and `Get`; the built
   app is still scanned by the Stop/pre-commit detector.
8. **Visual proof of the build.** Screenshot the implemented app at desktop and
   mobile only when needed for QA; this is not a design-direction step and it
   does not start a design server.
9. **Default AI tells are banned** unless the brief explicitly asks: Inter /
   default system fonts, purple-violet gradients, nested cards, side-tab accent
   borders, decorative status dots, em-dash-heavy copy, fake product UI made of
   styled divs. The detector catches the measurable ones; you own the rest.
10. **Component library is an implementation decision, made after the pick.**
    Choose one from the stack and the job, not by reflex:
    - React/Next: **shadcn/ui + Radix + Tailwind**; add only the components used
      (`npx shadcn@latest add ...`).
    - Vue: **Nuxt UI**; Svelte: **Skeleton**; Angular: **Spartan / NG-ZORRO**.
    - Marketing-only page: no library unless the page will be reused.
    - One library, no component MCP, no full kit dump. Record the choice and the
      reason in `AGENTS.md` or `DESIGN.md`.
