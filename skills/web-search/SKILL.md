---
name: web-search
description: >
  Web search and link-fetch routing for this harness. Use whenever the task needs
  current info, web links, or page content (searching the web, fetching a URL, fact-checking,
  research). Native web_search/web_fetch are the default (pinned to deepseek-flash);
  Exa MCP is for deep research and fallback. No xAI seats.
user-invocable: true
---

# Web search routing

You are in a **multi-model harness**. Search/fetch goes through the tools below — **do not switch the session model** to change search behavior.

## Tools

| Tool | What it does |
|------|----------------|
| built-in `web_search` | Native CLI search, pinned via `[models] web_search = "deepseek-flash"` — backend search on api.deepseek.com. Cheap, metered per request. |
| built-in `web_fetch` | Native URL → markdown. Enabled via `[features] web_fetch = true` / `GROK_WEB_FETCH=1`. |
| `exa__web_search_exa` | Exa MCP search |
| `exa__web_fetch_exa` | Exa MCP page fetch |

## Routing rules (in order)

1. **Default: native `web_search` / `web_fetch`.** They resolve to `deepseek-flash` in every profile, so they are cheap and quota-safe. Use for routine lookups, links, and docs facts.
2. **Use Exa MCP when:** the native call is denied or errors; you need deep or multi-source research; or the user explicitly asks for Exa. On a denial, switch to Exa without asking.
3. **Deep research from a Flash parent:** spawn a `deepseek-flash` subagent and let **that child** use native search, or use Exa; keep the parent on its seat.
4. **Do not switch the whole session model** just to search. There are no xAI seats anymore (retired 2026-10-17, HTTP 402).

## First-time setup note (if native tools are denied)

Grok CLI also reads `~/.claude/settings.json`. A `permissions.deny` of `WebSearch` / `WebFetch` there blocks native tools even in always-approve mode. Remove those deny entries; `deny` always wins.

Exa MCP fallback: `[mcp_servers.exa]` in `~/.grok/config.toml`. First use is OAuth. If missing: `/mcps` → `r`.

## What you must not claim

- Do not claim Exa *is* the built-in `web_search` backend.
- Do not claim the retired grok seats are available for native search.
- Do not burn a subagent spawn for a single lookup that native `web_search` can do.
