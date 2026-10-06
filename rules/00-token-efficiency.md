# Token efficiency (home rules — apply in every session)

## Web search / fetch (automatic, seat-aware)
- **On Grok seats** (`grok-4.6`, `grok-4.5`, `grok-build`): use native `web_search` and `web_fetch` only. Do **not** use Exa MCP unless the user explicitly asks for Exa.
- **On DeepSeek and other non-Grok seats:** prefer Exa MCP (`exa__web_search_exa`, `exa__web_fetch_exa`). If native `web_fetch` is denied or errors on those seats, fall back to Exa without asking.

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
- **DeepSeek V4.1 Flash or Grok:** read images directly on the current seat. Do not spawn a vision subagent.
- **Gemini seats are unplugged.** Do not `/model gemini-*` or spawn `gemini-image`.
- **If a seat rejects an image** (a 400 on `image_url`, or the provider is text-only): do not invent pixels; ask the user to re-attach it on DeepSeek or Grok.
- Images cost tokens (DeepSeek bills image input). Prefer one screenshot; do not re-send the same image every turn if a text summary already exists.
