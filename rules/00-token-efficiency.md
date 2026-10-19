# Token efficiency (home rules — apply in every session)

## Skill routing (automatic)
- Before a multi-step build, design, debug, review, research or video task, run
  the router's `skill-search` and read at most **1–3** matching `SKILL.md` files.
  Packs stay unlinked; never load a whole pack.

## Web search / fetch (automatic)
- Native `web_search` / `web_fetch` are pinned to `deepseek-flash` in every profile (backend search on api.deepseek.com). They are the cheap default for routine lookups.
- Prefer Exa MCP (`exa__web_search_exa`, `exa__web_fetch_exa`) for deep or multi-source research, and whenever a native call is denied or errors. Do not switch the session model just to search.

## Token-lean defaults (automatic)
- Keep replies concise. Answer first, then supporting detail. No restating the request, no summaries of what was just done unless asked.
- Read files partially (`limit` / `offset`) when only part is needed; use `grep` instead of reading whole files to find things; prefer targeted `search_replace` edits over full-file rewrites.
- Batch independent tool calls into one turn (parallel calls) instead of serial one-at-a-time calls.
- Never re-read or re-dump file contents that are already in the conversation; reuse prior tool output instead.
- Keep tool outputs out of the visible reply: report results, not raw dumps.

## Session hygiene (automatic)
- Prefer resuming a recent session (warm cache, no re-prefill) over starting a new one when the work continues from it.
- When a session's context is large (100K+ tokens), suggest or run `/compact` rather than letting it grow.
- Keep handoff briefs short (the README rule: they are the bus between sessions, not transcript dumps).

## Image handling (automatic)
- **Multimodal seats (`deepseek-flash`, `deepseek-flash-high`, `glm-flash`):** read images directly on the current seat. Do not spawn a vision subagent.
- **Text-only seats (`deepseek-pro`):** do not send images. Read the image on a Flash seat and pass a text description.
- **Gemini seats are unplugged.** Do not `/model gemini-*` or spawn `gemini-image`. The xAI-hosted seats are retired.
- **If a seat rejects an image** (a 400 on `image_url`, or the provider is text-only): do not invent pixels; ask the user to re-attach it on `deepseek-flash`.
- Images cost tokens (DeepSeek bills image input). Prefer one screenshot; do not re-send the same image every turn if a text summary already exists.

## Memory (mem0 MCP, when connected)
- Retrieval is the metered side. One `search_memory` at session start when the task continues earlier work; otherwise on demand. Never per-turn.
- Store sparingly with `add_memory`: durable preferences, project conventions, painful-bug lessons — one line each. `capture-lesson` mirrors its lessons here.
