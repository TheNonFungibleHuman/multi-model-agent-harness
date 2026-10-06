# Multi-model agent harness

An operating layer for [Grok Build](https://x.ai/cli): four routed model seats, switchable config profiles, a skill shelf, and two Python daemons that record token cost and edit the live config from measured evidence. A small verification suite checks that the install still matches the rules in this repo.

The Grok binary, its tools, and its model client are xAI's. This repository is the layer around that binary. Fork it, change the seats and the policy, and install it onto your own `~/.grok`.

Measured on my machine from 12 Aug 2026 through 6 Oct 2026: **3,051** inferences across **197** sessions. **2,872** of those rows are priced on DeepSeek's published rate card, about **$3.23**, and **98.5%** of those prompt tokens were cache hits (432.4M of 438.8M). The ledger file is local and is not in this repo. The figures above are a snapshot, not a promise about your bill.

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
| `token-ledger\`, `verify\`, `rules\` | the same folders under `%USERPROFILE%\.grok\` |
| `shelf.ps1` | `%USERPROFILE%\grok-skill-shelf\shelf.ps1` |

It leaves `auth.json`, sessions, logs, `grok.exe`, and the ledger's data files (`usage.jsonl`, `session_stats.jsonl`, `changes.log`) untouched. If `config.toml` already exists, it stays. Pass `-ForceConfig` to replace it with this repo's starter, which is the lean profile.

Set a user-level `DEEPSEEK_API_KEY`, then launch through the wrapper so the key is loaded into the process:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.grok\start-grok.ps1"
```

Grok seats use `grok login` or `XAI_API_KEY`. To run the ledger and the tuner in the background:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.grok\token-ledger\register-startup.ps1"
```

That registers `GrokLedgerWatchdog`, every 15 minutes, through `run-hidden.vbs`, so a console window does not flash on the desktop.

## Make it yours

Edit the clone, then run `install.ps1` again. The clone is the source of truth.

| You want to | Edit |
| --- | --- |
| Add or remove a seat | `[model.*]` in `config.toml`, `config.lean.toml`, and `config.full.toml`, then the seat table in `skills/route/SKILL.md` and `skills/delegate/SKILL.md`, then `EXPECTED_SEATS` in `verify/verify_harness.py` |
| Change who plans and who implements | `[subagents.models]` and `[subagents.personas]` in all three configs |
| Change the daily default | `[models] default` in all three configs. The verifier requires them to agree. The starter default is `deepseek-flash` |
| Turn a pack of heavy skills on | `shelf.ps1` and the `/shelf-*` skills. Packs live under `%USERPROFILE%\grok-skill-shelf\` and are yours to add. This repo ships the switch, not the packs |
| Pin a context window or the reasoning default | `token-ledger/overrides.toml`. A pin is never overwritten by the tuner |
| Change when the window grows | `WINDOW_FLOOR`, `WINDOW_CAP`, `WINDOW_STEP`, and `RAISE_AT` in `token-ledger/tuner.py` |
| Allow another skill in the catalog | add its name to the set at the top of `verify/verify_skills.py`, or disable it under `[skills] disabled` |

`config.full.toml` enables fewer skill blocks and turns Open Design on. The Open Design paths in these files are placeholders (`C:\Path\To\Open Design`). Point them at your install before you use that server.

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
              verify_harness.py / verify_skills.py / test_switch_carry.py
```

**Seats.** The starter config has four, all direct to the provider:

| Seat | Role |
| --- | --- |
| `deepseek-flash` | Daily driver. DeepSeek V4.1 Flash at `api.deepseek.com`, effort `low` |
| `deepseek-flash-high` | The same model with effort `high` and a 16k output budget |
| `grok-4.5` | Planning, review, hard bugs. Also the `plan` subagent |
| `grok-4.6` | The model `[models] web_search` is pinned to |

Two DeepSeek rows exist because the tuner owns the global `default_reasoning_effort`. A single row would lose its high-effort preset every time the tuner pins the global default to `low`. The second row carries its own effort, which the tuner does not write.

**Policy skills.** `route`, `delegate`, and `web-search` tell the agent which seat does which work. On a Grok seat, search uses the native tools. On DeepSeek, search uses the Exa MCP server, because native search is pinned to `grok-4.6` and would spend that quota. `handoff` and `pull-handoff` pass a short brief to the next session. `capture-lesson` appends one rule to `~/.grok/lessons/LESSONS.md` after a real failure. The `profile-*`, `shelf-*`, and `mcp-design-*` skills are slash commands (`disable-model-invocation: true`).

**Shelf.** Optional skill packs sit in `%USERPROFILE%\grok-skill-shelf\` and are linked into `~/.grok\skills` with directory junctions. Turning a pack off removes the junction. The files stay on disk. `shelf.ps1` is the implementation. Bring your own packs; the third-party packs used on the author's machine are not redistributed here.

**Ledger.** `ledger.py` tails `unified.jsonl`, appends one row per `shell.turn.inference_done`, and prices DeepSeek traffic from the published card: cache hit $0.0028, cache miss $0.14, output $0.28, per million tokens. Rows attributed to other providers are recorded and kept out of that dollar total when `deepseek` is false. See `token-ledger/README.md` for the daemon commands.

**Tuner.** Every 15 minutes `tuner.py` may raise a seat's `context_window` when the last day's average peak context exceeds 80% of the declared window, or a session compacts 3 or more times. The step is 64K, the bounds are 128K–512K, and a seat changes at most once per 24 hours. It can pin `default_reasoning_effort` to `low` when reasoning tokens exceed 20% of output. It can disable the Paper MCP server after repeated handshake failures. It does not raise effort, and it does not lower a window.

**Checks.** `verify/verify_harness.py` parses all three configs and requires the same seat set and the same default, rejects retired seat names, checks that ports 8787, 8788, 8789, and 8791 have no listener, and checks the skill shelf. `verify/verify_skills.py` runs `grok inspect` and compares the enabled catalog to the sets at the top of the file. `verify/test_switch_carry.py` switches profiles against the live `config.toml` and restores the original bytes in a `finally` block. Run that one when you can afford a brief rewrite of the live file.

```powershell
python "$env:USERPROFILE\.grok\verify\verify_harness.py"
python "$env:USERPROFILE\.grok\verify\verify_skills.py"
python "$env:USERPROFILE\.grok\verify\test_switch_carry.py"
```

On a machine that has `~/grok-skill-shelf/core`, the harness check expects that pack to be linked and to contain `POLICY_SKILLS` plus `SHELF_CORE`. With no core shelf, it only requires the skills this repo ships.

## Decisions, with the failure that forced each one

**The context window is raise-only.** `context_window` is the auto-compaction trigger, so lowering it does not shrink the prompt. It only compacts sooner. An earlier rule lowered the window under 40% utilization. On 16 Aug 2026 it moved every seat from 262144 to 196608, and a later pass moved them back. The lower path was removed on 10 Sep 2026. The author's windows are now pinned at 500000 in `overrides.toml`, inside the 128K–512K bounds, so the raise path stays armed and the pin keeps them off the 524288 cap.

**The tuner refuses to write a config it cannot parse.** `tuner.py` runs `tomllib.loads` on the new text and prints `REFUSING to write invalid TOML` if parsing fails. The previous file stays. A timestamped `config.toml.bak-*` is written before the first automatic edit, and every applied change is appended to `changes.log`.

**Quoted seat names need quoted override keys.** `[model."grok-4.5"]` is quoted because the id contains dots. The tuner strips the `model.` prefix only, so the override key is `'"grok-4.5"'`, quotes included. A bare `grok-4.5` key nests under the wrong table and the pin never matches.

**Profile switches carry tuner state.** Copying `config.lean.toml` over `config.toml` used to wipe the windows and the reasoning default the tuner had just written. `carry_tuning.py` re-applies those keys after the template is installed. `test_switch_carry.py` is the regression test: it plants tuner state, switches, asserts the values survived, and restores the file byte for byte.

**Line endings are pinned.** `.gitattributes` is `* -text`. A checkout that rewrote LF to CRLF once left literal `\r` sequences in `config.toml`, and the verifier now fails a config that contains that pattern. The tuner writes the file with `newline="\n"`.

**Slash-only toggles are free, and that was measured.** On 10 Sep 2026, disabling all 14 toggle skills moved a live prompt by about 2 tokens. Five model-invocable skills moved it by 463. Flipping the flag off on five toggles added 271. The toggles stay in the repo because they are the in-session switches, and `verify_skills.py` reads each toggle's frontmatter and requires `disable-model-invocation: true`.

**One git directory, the work tree left in place.** Scheduled tasks and `start-grok.ps1` call absolute paths under `~/.grok`. The author's live tree is versioned with `git init --separate-git-dir`, so those paths never moved. This public repo is the slice that is safe to fork: policy, automation, configs, and checks. It does not contain API keys, session transcripts, the official CLI, or other people's skill packs.

**Retired local proxies stay retired.** Earlier seats reached providers through localhost shims on ports 8787 (DeepSeek), 8788 (Gemini), 8789 (Zen), and 8791 (a Zen relay). The current seats talk to the provider directly. `verify_harness.py` fails if any of those ports is listening or if a `zen-relay` folder comes back. `start-grok.ps1` does not start them.

## Scope

Claim the routing policy, the profile and shelf switches, the ledger, the tuner, and the checks. The agent runtime is a third-party product. Skill packs such as the Matt Pocock set are used on the author's machine and are not included here; `SHELF_CORE` in the verifiers names them so a machine that has the shelf still has to match it.

License: MIT.
