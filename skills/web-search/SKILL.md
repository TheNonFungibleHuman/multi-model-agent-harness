---
name: web-search
description: >
  Web search and link-fetch routing for this harness. Use whenever the task needs
  current info, web links, or page content (searching the web, fetching a URL, fact-checking,
  research). On Grok seats use native web_search/web_fetch. On DeepSeek and
  other non-Grok seats prefer Exa MCP so Grok quota is not burned.
user-invocable: true
---

# Web search routing (seat-aware)

You are in a **multi-model harness**. Search/fetch routing depends on the **current session model**.

## Tools

| Tool | What it does |
|------|----------------|
| built-in `web_search` | Native Grok CLI search. All three profiles pin `[models] web_search = "grok-4.6"`, so it resolves to the Grok seat. |
| built-in `web_fetch` | Native URL → markdown. Enabled via `[features] web_fetch = true` / `GROK_WEB_FETCH=1`. |
| `exa__web_search_exa` | Exa MCP search |
| `exa__web_fetch_exa` | Exa MCP page fetch |

## Routing rules (in order)

1. **Current model is Grok** (`grok-4.6`, `grok-4.5`, `grok-build`, or any `grok-*`):
   - Use **native** `web_search` and `web_fetch`.
   - **Do not** call Exa MCP unless the user explicitly asks for Exa.
   - If native `web_fetch` is permission-denied, say so — do not silently switch to Exa on a Grok seat.

2. **Current model is DeepSeek or another non-Grok seat:**
   - Prefer **Exa** (`exa__web_search_exa`, `exa__web_fetch_exa`) so routine lookups do not burn Grok quota.
   - Native `web_search` is acceptable if Exa is down. On lean/full that native tool is DeepSeek-backed.
   - If native `web_fetch` is denied or errors, use Exa without asking.

3. **Deep research** where Grok's judgment is the point:
   - If already on Grok: native tools on this seat.
   - If on DeepSeek and Grok quota is available: spawn a Grok subagent (`model: grok-4.6` or `grok-4.5`) and let **that child** use native search. Parent keeps the short summary.
   - If Grok quota is out (`429` / user says exhausted): stay on DeepSeek and use Exa.

4. **Do not switch the whole session model** just to search.

## First-time setup note (if native tools are denied)

Grok CLI also reads `~/.claude/settings.json`. A `permissions.deny` of `WebSearch` / `WebFetch` there blocks native tools even in always-approve mode. Remove those deny entries; `deny` always wins.

Exa MCP (DeepSeek path): `[mcp_servers.exa]` in `~/.grok/config.toml`. First use is OAuth. If missing: `/mcps` → `r`.

## What you must not claim

- Do not claim Exa *is* the built-in `web_search` backend.
- Do not use Exa on a Grok seat "to be safe" or because a home-rule fallback used to say so.
