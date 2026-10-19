---
name: delegate
description: >
  Multi-agent delegation policy for Grok Build: when DeepSeek (main) should
  spawn specialized subagents, which model/type to use, and when to run them
  in parallel. Use when starting multi-step work, Paper + vision, explore +
  implement, review before merge, or when the user says /delegate, "use
  subagents", "run in parallel", or "multi-agent".
user-invocable: true
---

# Delegate — main DeepSeek + specialist subagents

You are the **foreman** (usually **DeepSeek Flash** on the main session).  
Specialists are **subagents** with their own context. You integrate **short summaries** only.

This is **policy you follow**, not a hidden auto-router. Spawn when the table says so; do not fan out for trivial work.

## Parallelism — yes, Grok CLI supports it

| Capability | Supported? |
|------------|------------|
| Multiple subagents at once | **Yes** |
| How | Issue **multiple** `spawn_subagent` calls in one turn with `background: true` (default), then wait / collect results |
| Nested subagents (child spawns child) | **No** — max depth 1 |
| Same files edited by two writers in parallel | **Avoid** — conflicts / thrash |

**Parallel when:** read-only, different modalities, or independent scopes (e.g. explore auth + explore billing; vision QA + web research).  
**Sequential when:** one depends on the other, or both write the same paths / same Paper artboard.

```text
# Good parallel fan-out (one parent turn)
spawn_subagent(explore, "Find auth middleware…")     # background
spawn_subagent(explore, "Find rate-limit config…")   # background
→ await summaries → main DeepSeek implements (and reads screenshots itself)
```

## Seats (your harness)

| Role | Config / model id | Notes |
|------|-------------------|--------|
| Main bulk | `deepseek-flash` | Bulk foreman / implementer |
| Bulk + think (default) | `deepseek-flash-high` | Same model, higher effort. The config default daily driver. |
| **Judgment / hard** | **`deepseek-pro`** | Planning, nasty bugs, review. Also the `plan` subagent and both personas. Text-only. |
| Overflow bulk | `glm-flash` | Z.ai GLM 5.3 Flash (PAYG), 1M context, low effort. Alternative bulk seat; same rules — the pro seat still plans and debugs. |
| Explore children | `deepseek-flash` via `[subagents.models]` | Read-only search |
| **Plan children** | **`deepseek-pro`** via `[subagents.models].plan` | **Always the pro seat for real planning** |
| Vision | `deepseek-flash` or `glm-flash` on the current seat | Screenshots, Paper, mockups. Pro is text-only. **No Gemini, no xAI seats.** |
| **Nasty bugs / hard debug** | **`deepseek-pro`** | **Must spawn the pro seat** — not Flash alone |
| Review / architecture | `deepseek-pro` | Security, design judgment, go/no-go |
| Web facts | native `web_search` / `web_fetch` (pinned to `deepseek-flash`) | Exa MCP for deep research or fallback |
| Images create/edit | `image_gen` / `image_edit` tools | Not a chat subagent |

**No local proxies.** 8787, 8788, 8789 and 8791 are all retired — never start one to work around a seat error.

### Specialty split (explicit)

| Specialty | Model | When |
|-----------|--------|------|
| **Volume coding** | DeepSeek Flash | Default implement, tests, refactors |
| **Planning** | **DeepSeek Pro** | User wants a plan, multi-step design, “how should we build X”, architecture before code |
| **Nasty / hard bugs** | **DeepSeek Pro** | Heisenbugs, flaky, multi-system, security, “can’t repro”, Flash already failed, race/concurrency, production-only |
| **Vision** | `deepseek-flash` or `glm-flash` | Pixels / screenshots. Pro is text-only. Gemini unplugged. |
| **Explore map** | DeepSeek explore | “Where is X?” only |

Spawnable types (probe-confirmed on this build): `explore`, `general-purpose`, `plan`. The `[subagents.personas.*]` blocks in config are prompt overlays only — they do **not** create spawn types, so never pass `subagent_type: reviewer` or `planner` (the call fails with "Unknown subagent type").  
Pin **`model`** on spawn (e.g. `model: deepseek-pro`) and put specialty rules in the **child prompt**. For `plan`, config already sets the model to DeepSeek Pro.

## Task → specialist table

| User / situation | Do on main (DeepSeek)? | Spawn | Type | Model | Parallel OK? |
|------------------|------------------------|-------|------|-------|--------------|
| Trivial edit, rename, one-liner | **Yes alone** | — | — | — | — |
| Multi-file implement, tests | **Yes** (or drafter child) | optional drafter | `general-purpose` | `deepseek-flash` | No if same files as main |
| “Where is X?” / map codebase | Light grep OK | **explore** | `explore` | deepseek | **Yes** × independent queries |
| **Any non-trivial plan / design / “how should we…”** | **No — do not plan alone on Flash** | **planner** | `plan` or `general-purpose` | **`deepseek-pro`** | Usually 1 (optionally parallel with explore) |
| **Nasty / hard / subtle bug** | **No — do not debug alone after one weak try** | **debugger / reviewer** | `general-purpose` | **`deepseek-pro`** | 1 (explore may run first or in parallel) |
| Screenshot / Paper visual QA | **Yes — read on `deepseek-flash` / `glm-flash`** | — | — | — | n/a |
| Bug screenshot → fix | **Yes** (read image on main) | pro seat if nasty | `general-purpose` | **`deepseek-pro`** | Sequential for nasty |
| Paper design loop | Paper MCP on main; DeepSeek reads screenshots | — | — | — | Not two Paper writers |
| Security / merge review | No | **reviewer** | `general-purpose` | **`deepseek-pro`** | After implement |
| Architecture decision | No | **planner** | `plan` / `general-purpose` | **`deepseek-pro`** | 1 |
| Fresh API/docs facts | Call tool | — | — | `web_search` | N/A |
| Image generation | Tools on main | — | — | Imagine tools | Parallel gens OK |

## Child prompt contract (always)

Every spawn prompt must include:

1. **Goal** (one sentence)  
2. **Scope** (paths, artboard, constraints)  
3. **Output format** (bullets / files changed / go-no-go)  
4. **Do not** re-dump the whole repo; return a **short summary** for the parent  

### Vision child (template)

Do **not** spawn a Gemini vision child. Gemini seats are unplugged. Read images on `deepseek-flash` or `glm-flash` (the pro seat is text-only).

### Reviewer child (template)

```text
Strict review. Check correctness, edge cases, security, match to goal.
Return: summary, blockers, nits, go/no-go. Cite paths. No fluff.
```

`model`: **`deepseek-pro`** · high effort if available.

### Nasty-bug / hard-debug child (template) — **always DeepSeek Pro**

```text
You are the senior debugger (DeepSeek V4.1 Pro) on a hard debug. Parent is Flash (implementer only).
Symptoms: <paste>
What we tried: <paste>
Reproduce: <commands/paths if known>
Return ONLY:
- Root-cause hypothesis (ranked, with confidence)
- Evidence to gather / commands to run
- Minimal fix plan (files + steps)
- Risks / regressions
Do not implement large rewrites; hand a clear fix plan back to the parent.
```

`model`: **`deepseek-pro`** · `subagent_type`: `general-purpose` · high effort if available.

**Triggers (spawn the pro seat — do not keep thrashing Flash alone):**
- User says nasty / hard / flaky / heisenbug / race / production-only / security bug  
- Same issue failed **twice** on Flash  
- A Flash fix broke a p2p test (the measured conversion case)
- Multi-service or concurrency / memory corruption style symptoms  
- You are guessing without a clear root cause  

### Explore child (template)

```text
Read-only. Find where <X> lives. Return: key paths, 5–10 line summary, open questions.
Do not edit files.
```

`subagent_type`: `explore` · DeepSeek.

### Plan child (template) — **always DeepSeek Pro**

```text
You are the senior planner (DeepSeek V4.1 Pro) for a Flash implementer.
Goal: <user goal>
Constraints: <stack, deadlines, must-not-break>
Produce a sequenced plan:
1. Goals / non-goals
2. Steps (ordered), each with files/areas and acceptance checks
3. Risks & open questions
4. What Flash should implement first (smallest vertical slice)
Do not edit the codebase. Keep it actionable and short enough for the parent to execute.
```

`subagent_type`: **`plan`** (model is **`deepseek-pro`** via config) **or** `general-purpose` with `model: deepseek-pro`.

**Triggers (spawn the pro planner — do not plan solo on Flash):**
- User asks to **plan**, design approach, architecture, roadmap, or “how should we build…”  
- Multi-module feature before first commit  
- Risky migration / data / auth / payments design  

Tiny one-file plans can stay on main; anything non-trivial → **DeepSeek Pro**.

## Decision algorithm (each user turn)

```text
1. Is it trivial? → DeepSeek Flash alone.
2. Need pixels? → read them on `deepseek-flash` / `glm-flash`. Do not spawn Gemini.
3. Need a plan / architecture / “how should we…”? → MUST spawn pro planner (plan type or general-purpose model=deepseek-pro).
4. Nasty / hard / flaky bug or Flash failed twice? → MUST spawn pro debugger (model=deepseek-pro).
5. Need broad “where is X”? → 1–3 explore (DeepSeek) in parallel; may parallel with the pro plan.
6. Implement on main (Flash) from the pro seat’s plan / debug findings.
7. Risky ship / user asked review? → spawn pro reviewer.
8. Stale facts? → web_search on main.
```

## Parallel recipes

### A — Investigate then build

```text
parallel: explore(A), explore(B)
optional parallel: pro plan if design is unclear
→ main DeepSeek implements from summaries
```

### B — Plan then implement (**the pro seat plans**)

```text
sequential: DeepSeek Pro plan (subagent_type=plan, model=deepseek-pro)
→ main DeepSeek implements step 1 slice
→ tests
→ optional pro reviewer before ship
```

### C — Nasty bug (**the pro seat debugs**)

```text
optional parallel: explore(symptoms); parent reads any screenshot
→ DeepSeek Pro hard-debug (model=deepseek-pro)
→ main DeepSeek applies minimal fix from the pro plan
→ re-verify
```

### D — Paper on DeepSeek

```text
main: Paper edits
→ screenshot
→ DeepSeek reads the screenshot
→ main applies fixes
```

### E — Feature + visual bug

```text
parallel: explore("related code"); parent reads screenshot
if still unclear root cause → pro debug
→ main fixes
```

### F — Ship check

```text
main: finish tests
→ sequential: pro reviewer (deepseek-pro)
→ address blockers
```

## Anti-patterns

- **Planning a multi-step feature only on Flash** when the user asked for a plan — **spawn DeepSeek Pro**  
- **Thrashing Flash on a nasty bug** instead of spawning the pro seat  
- **Blanket pro retries on every failure** (measured: 1/33 conversions for +8% cost/solved)  
- Spawning 5 general-purpose editors on the same module  
- `/model gemini-*` or spawning `gemini-image` — those seats are unplugged  
- Pasting full child transcripts into parent  
- Claiming “automatic fusion” of all models as one brain  
- Explore children that edit files (use `explore` type — read-only)  
- Vision child that rewrites the whole design doc instead of bullets  

## Parent integration checklist

After children return:

1. If the pro seat planned → execute the **first vertical slice** on Flash  
2. If the pro seat debugged → apply **minimal fix** only; re-test  
3. Run tests / Paper screenshot as needed  
4. Pro reviewer before declaring risky work done  

## Related

- **route** — seat list and effort  
- DeepSeek V4.1 Flash reads images natively (no Gemini, no 8787 strip-proxy)  

## Quick phrases

| User says | You do |
|-----------|--------|
| `/delegate` or “use subagents” | Apply this skill; state what you will spawn |
| “run in parallel” | Fan out independent explores/vision; pro plan/debug usually sequential |
| “save quota” | Flash for volume; **still spawn DeepSeek Pro for plan + nasty bugs** |
| “plan this” / “how should we build…” | **Must spawn pro planner** (`plan` / `deepseek-pro`) |
| “nasty bug” / “hard bug” / “flaky” / stuck twice | **Must spawn pro debugger** (`deepseek-pro`) |
| “review this” | Spawn DeepSeek Pro reviewer |
| “look at this screenshot” | Read it on `deepseek-flash` / `glm-flash`. No Gemini. |
