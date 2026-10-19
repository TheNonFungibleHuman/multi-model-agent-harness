---
name: route
description: >
  Multi-model routing policy for this harness. Use when starting a multi-step
  coding task, when choosing which model or subagent to use, when an image or
  screenshot is involved, when the user asks to save quota, or when
  they say /route. Keeps DeepSeek Flash as default bulk, DeepSeek Pro for hard
  judgment. Gemini seats and the xAI-hosted seats are retired.
user-invocable: true
---

# Multi-model routing (lean)

You are running in a **multi-model harness**. Follow this policy unless the user overrides it.

## Seats

| Seat | Config model id | Use for |
|------|-----------------|---------|
| **Bulk** | `deepseek-flash` | Volume workhorse: explore, draft code, refactors, tests, grepping, boilerplate |
| **Bulk + think (default)** | `deepseek-flash-high` | The config default daily driver: same Flash model at high effort. |
| **Judgment / hard** | `deepseek-pro` | **Planning**, **nasty/hard bugs**, architecture, security, multi-file design judgment, final review — spawn as subagent; Flash implements after. Text-only. |
| **Overflow bulk** | `glm-flash` | Z.ai GLM 5.3 Flash (PAYG): 1M context, reasoning always on at low effort. Alternative bulk seat to spread load or when DeepSeek is unavailable. |
| **Vision** | `deepseek-flash` / `glm-flash` (multimodal) | Read screenshots on the current seat. `deepseek-pro` is text-only. **No Gemini seats**, and the xAI-hosted grok seats were retired 2026-10-17 (balance exhausted, HTTP 402). |
| **Web search** | Native `web_search` / `web_fetch` (pinned to `deepseek-flash`) | Default path, cheap. Exa MCP (`exa__web_search_exa` / `exa__web_fetch_exa`) for deep research or when native fails. |

## Measured routing (bench-v1, 2026-10-18)

33 curated SWE-bench Lite tasks, flash-high first: **32/33 resolved, $0.2807 ($0.0088/solved)**.
Retrying every failure on `deepseek-pro`: **33/33, $0.3139 ($0.0095/solved)**, 1 conversion
(django-15400, a p2p regression). **Blanket auto-escalation is not the default.** Keep
flash-first; spend pro on planning, hard bugs, review, and a retry when flash broke a
p2p test or failed twice.

## Effort (per seat)

On the **current** model:

```text
/effort low
/effort medium
/effort high
/effort xhigh
```

Works when the seat has `supports_reasoning_effort = true` (DeepSeek and GLM seats).  
Prefer **seat defaults** (`deepseek-flash` = low, `deepseek-flash-high` / `deepseek-pro` = high), then nudge with `/effort` mid-session.

## Rules (in order)

1. **Stay lean.** Do not load skill shelves, extra MCP, or huge dumps "just in case." Load skills/MCP only when the task needs them.
2. **Default is DeepSeek Flash.** Config default is `deepseek-flash-high` — the daily driver. `deepseek-pro` is the
   judgment seat, spent on planning, hard bugs, and review, never on volume. That split is
   a **settled cost decision**; do not rebalance it toward the pro seat. Bulk alternatives when you want
   them: `deepseek-flash` (low effort) and `glm-flash` (Z.ai PAYG). `/model deepseek-pro` only when
   the whole session should be the pro seat.
2b. **No local proxies.** 8787 (DeepSeek strip), 8788 (Gemini), 8789 (Zen) and 8791 (the Zen relay for the Muse seats) are all retired — four seats, direct to the provider. Never start a `start.ps1` from a retired folder to "fix" a seat.
3. **Spawn DeepSeek Pro (do not keep thrashing Flash)** when:
   - **Planning:** user wants a plan, approach, architecture, roadmap, or “how should we build X” → spawn **`plan`** subagent or general-purpose with `model: deepseek-pro` (config pins plan → DeepSeek Pro). Flash then **implements** the plan.
   - **Nasty / hard bugs:** flaky, heisenbug, race, multi-system, security, production-only, unclear root cause, or **two Flash attempts failed** → spawn **DeepSeek Pro debugger/reviewer** (`model: deepseek-pro`). Flash applies the minimal fix.
   - security or irreversible decisions / final review before merge
   - How: **prefer spawn_subagent with `model: deepseek-pro`** so main stays on Flash; only `/model deepseek-pro` if the whole session should be the pro seat.
4. **Images / screenshots:**
   - **Multimodal seats (`deepseek-flash`, `deepseek-flash-high`, `glm-flash`):** read pixels on the current seat. Do not spawn a vision child.
   - **`deepseek-pro` is text-only:** do not send it images. Read the image on a Flash seat (or GLM) and pass a text description.
   - **Do not** `/model gemini-*` or spawn `gemini-image` — those seats are unplugged.
   - **A seat that rejects the image** (a 400 on `image_url`, or a genuinely text-only provider): do not invent pixels; describe what you cannot see and ask the user, or read it on `deepseek-flash` instead.
   - DeepSeek rejects images in `system` / `assistant` messages (400). User-message attachments are the supported path.
   - Trust the user over the model if a vision read conflicts with what they say is in the image.
5. **Subagents:**
   - Full task→specialist table + **parallel rules**: skill **delegate** (also `/delegate`).
   - `explore` → DeepSeek Flash (map codebase).
   - `plan` → **DeepSeek Pro** in config — **always use for real planning**.
   - Implementation bulk → DeepSeek Flash (main or drafter).
   - Nasty bugs + review → **DeepSeek Pro** (reviewer / hard-debug spawn).
   - **Parallel is supported**: multiple `spawn_subagent` (background) in one turn for independent work. No nested children. Don’t parallel-write the same files.
   - Children must return **short summaries** (what changed, paths, risks). Never paste full child transcripts into the parent.
6. **Web search / links:**
   - **Default:** native `web_search` / `web_fetch` — pinned to `deepseek-flash` (backend search on api.deepseek.com). Cheap; use for routine lookups.
   - **Exa MCP** (`exa__web_search_exa`, `exa__web_fetch_exa`) for deep or multi-source research, and as the fallback whenever a native call is denied or errors.
   - **Deep research from a Flash parent:** spawn a `deepseek-flash` subagent (native search) or use Exa; do not switch the session model.
   - Do **not** switch the whole session model just to search.
7. **Session handoff:** for another session or dashboard agent, use `/handoff` (write) and `/pull-handoff` (read). Prefer files under `~/.grok/handoffs/`.
8. **Learning:** after a real bug or failed approach, suggest `/capture-lesson` or write a short lesson yourself if the user wants lasting memory.

## What you must not claim

- Do **not** claim Gemini is wired in this harness. Those seats are unplugged.
- Do **not** claim the xAI-hosted grok seats work — they were retired 2026-10-17 (HTTP 402, balance exhausted).
- Do **not** claim sessions telepathically share full context without handoff/fork/dashboard.
- Routing is **policy you follow**, not a separate ML router product.

## Quick start phrases

- "Use Flash for this" → stay on Flash for implement; still DeepSeek Pro for plan/nasty bugs.
- "Plan this" / "how should we build…" → **spawn pro planner** (`plan` / deepseek-pro).
- "Nasty bug" / hard debug / stuck twice → **spawn pro debugger** (deepseek-pro).
- "Review on Pro" (or old "review on Grok" habits) → DeepSeek Pro reviewer path.
- "Screenshot / image" → read it on a multimodal seat (`deepseek-flash` / `glm-flash`). No Gemini, not on Pro.
- "Search the web / current info / find links" → native `web_search`/`web_fetch` first; Exa MCP for deep research.
- "Use subagents" / "in parallel" → skill **delegate**.
- "Save quota" → Flash for volume; **do not skip DeepSeek Pro on plan or nasty bugs**.

## Adding or removing a seat

Do this deliberately, and keep this skill's table and `~/.grok/config.toml` in
step.

1. Read the seat table below and the `[model]` / `[subagents.models]` entries in
`~/.grok/config.toml` before changing anything.
2. Add or remove the seat in **both** places, then state which model ids are now
live and which are gone.
3. An auth error ("Authentication required", "session has expired") is a
credential problem, not a seat-list problem. Name the provider and ask for a
fresh key (`/login`) instead of retrying the same call.
4. Never start a retired local proxy to "fix" a seat — see the retired ports
above. If a provider is unreachable, say which one and stop.
5. After editing the config, `/mcps` + `r` re-reads MCP servers; the model list is
read at session start. Say which of the two is needed.
6. Update the table in this skill in the same turn, so the next session does not
re-derive the seat list.
