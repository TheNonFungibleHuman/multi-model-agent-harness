# Operating layer for Grok Build

[Grok Build](https://x.ai/cli) is the underlying terminal coding assistant. This repository is the layer I built around it: model routing, cost telemetry, quality gates, and a design-review workflow. It does not ship Grok Build, the models, API keys, or personal session data.

## Why this exists

I kept hitting three problems in AI-assisted development:

1. **Design was an afterthought.** The UI got built before anyone agreed on the look.
2. **Every prompt carried skills the task didn't need.** The context was paying for a library it wasn't using.
3. **Model costs were invisible.** There was no per-session view of what the agent spent or why.

This layer fixes those problems: it reviews 2–3 designs on a pen.dev canvas before code, loads only the 1–3 skills a task needs, and records cost per session. The result is about **1,000 fewer prompt tokens per turn**, design decisions before implementation, and a ledger that shows where spend came from.

## Results at a glance

| Area | What changed | Measured result |
| --- | --- | --- |
| Model routing | 4 models, 3 profiles; the expensive model is reserved for planning, hard bugs, and retries | A 33-task benchmark showed blanket escalation solved +1 task (3%) for 8% more cost → the cheap model is the default |
| Cost telemetry | Async Python service logs every model call and prices it against provider rates | 3,000+ calls across 198 sessions; 2,872 priced; 98.5% cache hit on 438.8M tokens |
| Skill loading | 10 of 43 always-on skills moved to on-demand routing | ~1,000 fewer prompt tokens per turn |
| Hook latency | UI-quality checks scoped to files changed in the current task; 17-file integrity canary | 104s → ~12s per turn (8.7×); daily alerts on unexpected changes |
| Design workflow | pen.dev canvas, 2–3 directions, AI review, design spec before code | Design is reviewed before implementation; HTML mockup and local review page removed |
| MCP context | Pencil and Inspo off by default; the design lane enables them for a child session | Normal build turns stay at ~15.9k tokens; the parent never carries design tools |
| Safety | Isolation guard removed; auto-approve user-managed; Windows Sandbox recipe included | Untrusted repos can run in a disposable VM; no hidden path policy |

The cost figures are a snapshot from 12 Aug–18 Oct 2026, not a promise about your bill. The ledger file is local and is not in this repo.

## Install it on your Grok

You need Windows PowerShell 5.1, Python 3.11 or newer, and Grok Build already installed so that `%USERPROFILE%\.grok\bin\grok.exe` exists.

```powershell
git clone https://github.com/TheNonFungibleHuman/multi-model-agent-harness.git
cd multi-model-agent-harness
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

`install.ps1` copies this repo into the live harness:

| From the clone | Installed to |
| --- | --- |
| `config.lean.toml`, `config.full.toml`, the scripts | `%USERPROFILE%\.grok\` |
| `skills\` | `%USERPROFILE%\.grok\skills\` |
| `token-ledger\`, `verify\`, `rules\`, `hooks\`, `sandbox\` | the same folders under `%USERPROFILE%\.grok\` |
| `shelf.ps1` | `%USERPROFILE%\grok-skill-shelf\shelf.ps1` |

It leaves `auth.json`, sessions, logs, `grok.exe`, and the ledger's data files (`usage.jsonl`, `session_stats.jsonl`, `changes.log`) untouched. Skill names already linked into the shelf are kept as junctions, and the shelf's core copies of the six policy skills are refreshed. If `config.toml` already exists, it stays. Pass `-ForceConfig` to replace it with this repo's starter, which is the lean profile.

Set a user-level `DEEPSEEK_API_KEY`, then launch through the wrapper so the key is loaded into the process:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.grok\start-grok.ps1"
powershell -NoProfile -File "$env:USERPROFILE\.grok\start-grok.ps1" -Design -Inspo
```

Normal sessions have Pencil and Inspo **off**. `-Design` enables Pencil for that session; `-Inspo` enables Inspo; both are restored off on exit. The design lane does this for a child session automatically.

The provider seats read their API keys from the user environment (`DEEPSEEK_API_KEY`, `ZAI_API_KEY`); no xAI login is needed any more. To run the ledger and the tuner in the background:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.grok\token-ledger\register-startup.ps1"
```

That registers `GrokLedgerWatchdog`, every 15 minutes, through `run-hidden.vbs`, so a console window does not flash on the desktop.

For the policy-file canary (17 hooks/rules/gates), write a baseline once and install the daily task:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.grok\verify\integrity-canary.ps1" -Update
powershell -NoProfile -File "$env:USERPROFILE\.grok\verify\integrity-canary.ps1" -Install
```

## Make it yours

Edit the clone, then run `install.ps1` again. The clone is the source of truth.

| You want to | Edit |
| --- | --- |
| Add or remove a seat | `[model.*]` in `config.toml`, `config.lean.toml`, and `config.full.toml`, then the seat table in `skills/route/SKILL.md` and `skills/delegate/SKILL.md`, then `EXPECTED_SEATS` in `verify/verify_harness.py` |
| Change who plans and who implements | `[subagents.models]` and `[subagents.personas]` in all three configs |
| Change the daily default | `[models] default` in all three configs. The verifier requires them to agree. The starter default is `deepseek-flash-high` |
| Run one session on another seat | `start-grok.ps1 -m glm-flash` (the `-m` flag never writes config). The TUI `/model`/Ctrl+M picker saves the choice as the persistent default; `start-grok.ps1` snapshots the default at launch and restores it on exit, so `/model` is effectively session-scoped |
| Turn a pack of heavy skills on | `shelf.ps1` and the `/shelf-*` skills. Packs live under `%USERPROFILE%\grok-skill-shelf\` and are yours to add. This repo ships the switch, not the packs |
| Pin a context window or the reasoning default | `token-ledger/overrides.toml`. A pin is never overwritten by the tuner |
| Change when the window grows | `WINDOW_FLOOR`, `WINDOW_CAP`, `WINDOW_STEP`, and `RAISE_AT` in `token-ledger/tuner.py` |
| Allow another skill in the catalog | add its name to the set at the top of `verify/verify_skills.py`, or disable it under `[skills] disabled` |

`config.full.toml` changes the skill/seat profile; Pencil and Inspo stay off by default. Use `start-grok.ps1 -Design -Inspo` for a design session, or `design-lane.ps1` for a single canvas direction. The design lane is the preferred path because the parent session stays free of the design tools.

Profile switches go through `switch-profile.ps1`, which calls `token-ledger/carry_tuning.py`. The templates stay the profile defaults. The live per-seat `context_window`, `default_reasoning_effort`, and the watched MCP `enabled` flags are written back on top, so a switch keeps what the tuner (or you) already set.

After a new skill name shows up in `verify_skills.py` as unexpected, either disable it or add it to `POLICY`, `TOGGLES`, `BUNDLED`, or `SHELF_CORE`. That file is the catalog lock.

## How the pieces fit

```text
grok.exe  --->  ~/.grok/logs/unified.jsonl
                         |
                    ledger.py  --->  usage.jsonl + session_stats.jsonl + report.md
                         |
                    tuner.py   --->  config.toml
                         ^                (parse, then write; bounds; one change per seat per day)
                         |
              switch-profile.ps1 --> carry_tuning.py
                         |
              verify_harness.py / verify_skills.py / test_switch_carry.py / integrity-canary.ps1
```

**Design lane.** `design-lane.ps1` starts a child `grok -Design -Inspo` session, which loads Pencil and Inspo for that child only. The child produces canvas directions, exports `preview.png`, and exits; the parent build session never carries the design MCPs. The lane asks for user references first and falls back to Inspo when there are none.

**Seats.** The starter config has four, all direct to the provider:

| Seat | Role |
| --- | --- |
| `deepseek-flash` | Volume workhorse. DeepSeek V4.1 Flash at `api.deepseek.com`, effort `low` |
| `deepseek-flash-high` | The starter default: the same model at effort `high` with a 16k output budget |
| `deepseek-pro` | Judgment seat: V4.1 Pro (text-only, effort `high`) for planning, review, hard bugs. The `plan` subagent and both personas run here |
| `glm-flash` | Z.ai GLM 5.3 Flash (PAYG) at `api.z.ai`, native 1M context, effort `low`. Needs `ZAI_API_KEY` |

The xAI-hosted `grok-*` seats were retired when the Grok Build balance ran out (HTTP 402, 17 Oct 2026); they are hidden from the picker and no policy points at them.

The two `deepseek-flash` rows exist because the tuner owns the global `default_reasoning_effort`. A single row would lose its high-effort preset every time the tuner pins the global default to `low`. The second row carries its own effort, which the tuner does not write.

**Policy skills.** `route`, `delegate`, and `web-search` tell the agent which seat does which work. Native `web_search`/`web_fetch` are pinned to `deepseek-flash` (cheap, backend-search capable) and are the first choice; the Exa MCP server stays for deep research and as the fallback when a native call is denied or errors. `handoff` and `pull-handoff` pass a short brief to the next session. `capture-lesson` appends one rule to `~/.grok/lessons/LESSONS.md` after a real failure. `skill-router` keeps the optional shelf packs unlinked and loads only the 1–3 skills a task needs, on demand; it also carries the design-stack policy (Impeccable, Taste, Jakub, Emil). `product-build` is the end-to-end conductor: grill → spec → design gate → plan on pro → implement on flash → verify → review → handoff, with the detector as a hard gate. The `profile-*`, `shelf-*`, and `mcp-design-*` skills are slash commands (`disable-model-invocation: true`).

**Continuity.** `start-grok.ps1` starts a hidden context watcher for interactive sessions. At 70% context it writes a handoff to `~/.grok/handoffs` and toasts **`/new`, then `/pull-handoff <file>`** — no exit needed. The watcher keeps running across `/new` and reminds the new session to load the handoff. A new process can use `-ResumeHandoff` instead. `capture-lesson` also refreshes `rules/03-lessons.md` (top 12 rules, loaded every session); a `SessionEnd` hook regenerates it.

**Memory.** The hosted mem0 MCP server gives sessions a small cross-tool memory. The config holds only `X-API-Key = "${MEM0_API_KEY}"`; the key itself lives in a user environment variable. Retrieval is session-start and on-demand only — `rules/00-token-efficiency.md` keeps it token-lean.

**Shelf.** Optional skill packs sit in `%USERPROFILE%\grok-skill-shelf\` and are linked into `~/.grok\skills` with directory junctions. Turning a pack off removes the junction. The files stay on disk. `shelf.ps1` is the implementation. Bring your own packs; the third-party packs used on the author's machine are not redistributed here.

**Ledger.** `ledger.py` tails `unified.jsonl`, appends one row per `shell.turn.inference_done`, and prices DeepSeek traffic from the published card: cache hit $0.0028, cache miss $0.14, output $0.28, per million tokens. Rows attributed to other providers are recorded and kept out of that dollar total when `deepseek` is false. See `token-ledger/README.md` for the daemon commands.

**Tuner.** Every 15 minutes `tuner.py` may raise a seat's `context_window` when the last day's average peak context exceeds 80% of the declared window, or a session compacts 3 or more times. The step is 64K, the bounds are 128K–512K, and a seat changes at most once per 24 hours. It can pin `default_reasoning_effort` to `low` when reasoning tokens exceed 20% of output. It can disable the Paper MCP server after repeated handshake failures. It does not raise effort, and it does not lower a window.

**Isolation (Windows).** Grok's kernel sandbox is Linux/macOS only. On this host a PreToolUse `isolation-guard.py` restricts writes to the workspace, `%TEMP%`, and `~/.grok/handoffs`; denies reads/writes of `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.env`, and harness state (`auth.json`, `sessions`, `token-ledger`); denies destructive shell commands; checks subagent cwd; and inspects `use_tool` recursively. Feature work uses native git worktrees (`grok --worktree=<name>`). This is a guard, not a VM — untrusted code needs Windows Sandbox or a VM. See `rules/04-isolation.md`.

**Gates and metrics.** Stop hooks layer the Impeccable design detector, the anti-slop block (changed UI files must be detector-clean), and an evidence gate (code changed → the final message must name a test command and result, or the exact blocker). `SessionEnd` appends one trajectory record per primary session to `~/.grok/metrics/sessions.jsonl` (turns, tool calls, context peak, tokens, duration, edit volume) and refreshes the lessons digest. `python ~/.grok/skills/skill-router/scripts/metrics-report.py` prints per-model averages. The pre-commit guard is installed per project with `install-design-guard.ps1`.

**Checks.** `verify/verify_harness.py` parses all three configs and requires the same seat set and the same default, rejects retired seat names, checks that ports 8787, 8788, 8789, and 8791 have no listener, and checks the skill shelf. `verify/verify_skills.py` runs `grok inspect` and compares the enabled catalog to the sets at the top of the file. `verify/test_switch_carry.py` switches profiles against the live `config.toml` and restores the original bytes in a `finally` block. Run that one when you can afford a brief rewrite of the live file.

```powershell
python "$env:USERPROFILE\.grok\verify\verify_harness.py"
python "$env:USERPROFILE\.grok\verify\verify_skills.py"
python "$env:USERPROFILE\.grok\verify\test_switch_carry.py"
```

On a machine that has `~/grok-skill-shelf/core`, the harness check expects that pack to be linked and to contain `POLICY_SKILLS` plus `SHELF_CORE`. With no core shelf, it only requires the skills this repo ships.

## Design gate (Pencil only)

No UI code starts until the user has picked a direction. The flow is:

1. Ask for references: URLs, screenshots, notes, or “use Inspo.”
2. Run the design lane, which starts a child session with Pencil (and Inspo):
   ```powershell
   powershell -File "$env:USERPROFILE\.grok\skills\skill-router\scripts\design-lane.ps1" `
     -Brief "<direction brief>" -Cwd . -Out .\design\directions\<name> `
     -References "https://ref1, C:\refs\shot.png, editorial but not cream"
   ```
3. Review 2–3 canvas directions against `rules/02-design-gate.md`: hierarchy,
   type, palette/contrast, spacing, one CTA, no banned tells, originality.
   Fix or reject in the canvas before showing the user.
4. The user picks in Pencil. Write `DESIGN.md` from the chosen frame.
5. Choose the component library after the pick (React/Next → shadcn/ui + Radix
   + Tailwind; Vue → Nuxt UI; Svelte → Skeleton; Angular → Spartan/NG-ZORRO).
   One library, no component MCP, no full-kit dump.

There is no HTML/CSS mockup stage and no review server. Inspo is the free
reference source when the user has none; it is queryable over MCP and never
copy-pasted 1:1.

## Decisions, with the failure that forced each one

**The context window is raise-only.** `context_window` is the auto-compaction trigger, so lowering it does not shrink the prompt. It only compacts sooner. An earlier rule lowered the window under 40% utilization. On 16 Aug 2026 it moved every seat from 262144 to 196608, and a later pass moved them back. The lower path was removed on 10 Sep 2026. The author's windows are now pinned at 500000 in `overrides.toml`, inside the 128K–512K bounds, so the raise path stays armed and the pin keeps them off the 524288 cap.

**The tuner refuses to write a config it cannot parse.** `tuner.py` runs `tomllib.loads` on the new text and prints `REFUSING to write invalid TOML` if parsing fails. The previous file stays. A timestamped `config.toml.bak-*` is written before the first automatic edit, and every applied change is appended to `changes.log`.

**Quoted seat names need quoted override keys.** A seat id that contains dots, such as `[model."my.seat"]`, is quoted in `config.toml`. The tuner strips the `model.` prefix only, so the override key is `'"my.seat"'`, quotes included. A bare `my.seat` key nests under the wrong table and the pin never matches.

**Profile switches carry tuner state.** Copying `config.lean.toml` over `config.toml` used to wipe the windows and the reasoning default the tuner had just written. `carry_tuning.py` re-applies those keys after the template is installed. `test_switch_carry.py` is the regression test: it plants tuner state, switches, asserts the values survived, and restores the file byte for byte.

**Line endings are pinned.** `.gitattributes` is `* -text`. A checkout that rewrote LF to CRLF once left literal `\r` sequences in `config.toml`, and the verifier now fails a config that contains that pattern. The tuner writes the file with `newline="\n"`.

**Slash-only toggles are free, and that was measured.** On 10 Sep 2026, disabling all 14 toggle skills moved a live prompt by about 2 tokens. Five model-invocable skills moved it by 463. Flipping the flag off on five toggles added 271. The toggles stay in the repo because they are the in-session switches, and `verify_skills.py` reads each toggle's frontmatter and requires `disable-model-invocation: true`.

**One git directory, the work tree left in place.** Scheduled tasks and `start-grok.ps1` call absolute paths under `~/.grok`. The author's live tree is versioned with `git init --separate-git-dir`, so those paths never moved. This public repo is the slice that is safe to fork: policy, automation, configs, and checks. It does not contain API keys, session transcripts, the official CLI, or other people's skill packs.

**Retired local proxies stay retired.** Earlier seats reached providers through localhost shims on ports 8787 (DeepSeek), 8788 (Gemini), 8789 (Zen), and 8791 (a Zen relay). The current seats talk to the provider directly. `verify_harness.py` fails if any of those ports is listening or if a `zen-relay` folder comes back. `start-grok.ps1` does not start them.

## Scope

Claim the routing policy, the profile and shelf switches, the ledger, the tuner, the design lane, and the checks. The agent runtime is a third-party product. Pencil (pen.dev) and Inspo are third-party MCP servers; their tools, data, and terms are theirs. Skill packs such as the Matt Pocock set are used on my machine and are not included here; `SHELF_CORE` in the verifiers names them so a machine that has the shelf still has to match it.

License: MIT.
