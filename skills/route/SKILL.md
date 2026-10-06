---
name: route
description: >
  Multi-model routing policy for this harness. Use when starting a multi-step
  coding task, when choosing which model or subagent to use, when an image or
  screenshot is involved, when the user asks to save Grok/Gemini quota, or when
  they say /route. Keeps DeepSeek as default bulk, Grok for hard judgment.
  Gemini seats are unplugged.
user-invocable: true
---

# Multi-model routing (lean)

You are running in a **multi-model harness**. Follow this policy unless the user overrides it.

## Seats

| Seat | Config model id | Use for |
|------|-----------------|---------|
| **Bulk** | `deepseek-flash` | Default main model, explore, draft code, refactors, tests, grepping, boilerplate |
| **Bulk + think** | `deepseek-flash-high` | Same Flash model, default `/effort high`. `deepseek-pro` was removed — it was identical to this seat. |
| **Hard** | `grok-4.5` | **Planning**, **nasty/hard bugs**, architecture, security, multi-file design judgment, final review — spawn as subagent; DeepSeek implements after |
| **Vision** | DeepSeek V4.1 Flash or Grok | Read screenshots on the current seat. **No Gemini seats**, and the OpenCode Zen/Muse seats were removed 2026-09-10. |
| **Web search (Grok seat)** | Native `web_search` / `web_fetch` | **On Grok 4.6 / 4.5:** use native tools only. Do not use Exa unless the user asks. |
| **Web search (DeepSeek seat)** | **Exa MCP** (`exa__web_search_exa` / `exa__web_fetch_exa`) | Quota-free on DeepSeek. All profiles pin `[models] web_search = "grok-4.6"`, so native search resolves to the Grok seat, not DeepSeek. |

## Effort (like Grok)

On the **current** model:

```text
/effort low
/effort medium
/effort high
/effort xhigh
```

Works when the seat has `supports_reasoning_effort = true` (DeepSeek and native Grok).  
Prefer **seat defaults** (`deepseek-flash` = low, `deepseek-flash-high` = high), then nudge with `/effort` mid-session.

## Rules (in order)

1. **Stay lean.** Do not load skill shelves, extra MCP, or huge dumps "just in case." Load skills/MCP only when the task needs them.
2. **Default is DeepSeek.** Config default is `deepseek-flash` — the daily driver. Grok is the
   expensive seat, so it is spent on planning and hard judgment, never on volume. That split is
   a **settled cost decision**; do not rebalance it toward Grok. `/model grok-4.6` only when the
   whole session should be Grok.
2b. **No local proxies.** 8787 (DeepSeek strip), 8788 (Gemini), 8789 (Zen) and 8791 (the Zen relay for the Muse seats) are all retired — four seats, direct to the provider. Never start a `start.ps1` from a retired folder to "fix" a seat.
3. **Spawn Grok 4.5 (do not keep thrashing DeepSeek)** when:
   - **Planning:** user wants a plan, approach, architecture, roadmap, or “how should we build X” → spawn **`plan`** subagent or general-purpose with `model: grok-4.5` (config pins plan → Grok). DeepSeek then **implements** the plan.
   - **Nasty / hard bugs:** flaky, heisenbug, race, multi-system, security, production-only, unclear root cause, or **two DeepSeek attempts failed** → spawn **Grok debugger/reviewer** (`model: grok-4.5`). DeepSeek applies the minimal fix.
   - security or irreversible decisions / final review before merge
   - How: **prefer spawn_subagent with `model: grok-4.5`** so main stays DeepSeek; only `/model grok-4.5` if the whole session should be Grok.
4. **Images / screenshots:**
   - **DeepSeek V4.1 Flash or Grok:** read pixels on the current seat. Do not spawn a vision child.
   - **Do not** `/model gemini-*` or spawn `gemini-image` — those seats are unplugged.
   - **A seat that rejects the image** (a 400 on `image_url`, or a genuinely text-only provider): do not invent pixels; describe what you cannot see and ask the user, or stay on DeepSeek/Grok with a user-attached image.
   - DeepSeek rejects images in `system` / `assistant` messages (400). User-message attachments are the supported path.
   - Trust the user over the model if a vision read conflicts with what they say is in the image.
5. **Subagents:**
   - Full task→specialist table + **parallel rules**: skill **delegate** (also `/delegate`).
   - `explore` → DeepSeek (map codebase).
   - `plan` → **Grok 4.5** in config — **always use for real planning**.
   - Implementation bulk → DeepSeek (main or drafter).
   - Nasty bugs + review → **Grok 4.5** (reviewer / hard-debug spawn).
   - **Parallel is supported**: multiple `spawn_subagent` (background) in one turn for independent work. No nested children. Don’t parallel-write the same files.
   - Children must return **short summaries** (what changed, paths, risks). Never paste full child transcripts into the parent.
6. **Web search / links — seat-aware:**
   - **On Grok:** native `web_search` / `web_fetch` only. Do **not** use Exa unless the user asks.
   - **On DeepSeek and other non-Grok seats:** Exa MCP (`exa__web_search_exa`, `exa__web_fetch_exa`). Native `web_search` is a fallback.
   - **Deep research from a DeepSeek parent:** spawn a Grok subagent (`model: grok-4.6` or `grok-4.5`) to search natively if quota is available; otherwise Exa on DeepSeek.
   - Do **not** switch the whole session model just to search.
7. **Session handoff:** for another session or dashboard agent, use `/handoff` (write) and `/pull-handoff` (read). Prefer files under `~/.grok/handoffs/`.
8. **Learning:** after a real bug or failed approach, suggest `/capture-lesson` or write a short lesson yourself if the user wants lasting memory.

## What you must not claim

- Do **not** claim Gemini is wired in this harness. Those seats are unplugged.
- Do **not** claim sessions telepathically share full context without handoff/fork/dashboard.
- Routing is **policy you follow**, not a separate ML router product.

## Quick start phrases

- "Use Flash for this" → stay on DeepSeek for implement; still Grok for plan/nasty bugs.
- "Plan this" / "how should we build…" → **spawn Grok planner** (`plan` / grok-4.5).
- "Nasty bug" / hard debug / stuck twice → **spawn Grok debugger** (grok-4.5).
- "Review on Grok" → Grok reviewer path.
- "Screenshot / image" → read it on DeepSeek V4.1 or Grok. No Gemini.
- "Search the web / current info / find links" → **native `web_search`/`web_fetch` on Grok**; **Exa MCP** on DeepSeek. Spawn a **Grok** subagent for deep research from a DeepSeek parent only if Grok quota is available.
- "Use subagents" / "in parallel" → skill **delegate**.
- "Save quota" → DeepSeek for volume; **do not skip Grok on plan or nasty bugs**.

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
