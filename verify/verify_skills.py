"""Assert the live skill catalog matches the sets at the top of this file.

Edit the sets when you enable or retire a skill. POLICY and TOGGLES are the
skills this repo installs. SHELF_CORE is required only when
~/grok-skill-shelf/core exists, because those packs are not in this repo.
"""
import json
import os
import pathlib
import subprocess
import sys

GROK = os.path.join(os.environ["USERPROFILE"], ".grok", "bin", "grok.exe")

POLICY = {
    "route", "delegate", "web-search", "capture-lesson", "handoff", "pull-handoff",
    "skill-router", "product-build",
}
TOGGLES = {
    "shelf-core-on", "shelf-design-on", "shelf-extras-on", "shelf-firecrawl-on",
    "shelf-matt-on", "shelf-pstack-on", "shelf-off", "shelf-status", "shelf-video-on",
    "mcp-design-on", "mcp-design-off", "mcp-design-status",
    "profile-full", "profile-lean", "profile-status",
}
BUNDLED = {
    "build-with-ai", "create-skill", "imagine", "implement", "learn",
    "long-running-background-tasks", "review", "statusline",
}
# The author's own user skills, kept model-invocable on purpose.
# Counted only when present, so a clone without them still passes.
USER_SKILLS = {
    "local-preview", "token-discipline",
}
# Third-party skills. Required only when the core shelf pack is installed.
SHELF_CORE = {
    "code-review", "diagnosing-bugs", "tdd", "codebase-design", "domain-modeling",
    "find-skills", "here-now", "resolving-merge-conflicts", "wizard", "writing-for-agents",
}

raw = subprocess.run([GROK, "inspect", "--json"], capture_output=True, text=True,
                     encoding="utf-8-sig", timeout=180)
if raw.returncode != 0:
    print("inspect failed:", raw.stderr[:400])
    sys.exit(1)

j = json.loads(raw.stdout)
skills = j["skills"]
by_name = {s["name"]: s for s in skills}
enabled = {s["name"] for s in skills if not s.get("disabled")}
shelf_core = pathlib.Path.home() / "grok-skill-shelf" / "core"
core = POLICY | (SHELF_CORE if shelf_core.is_dir() else set())
user = {n for n in USER_SKILLS if n in by_name}
expected = POLICY | TOGGLES | BUNDLED | user

problems = []
for leak in sorted(enabled - expected):
    src = next(s["source"]["path"] for s in skills if s["name"] == leak)
    problems.append(f"unexpected enabled skill: {leak}  ({src})")
for miss in sorted(expected - enabled):
    problems.append(f"expected skill not enabled: {miss}")

leaked_roots = [s["name"] for s in skills
                if s["source"]["type"] == "user"
                and ".agents" in s["source"]["path"].replace("/", "\\")
                and not s.get("disabled")]
for name in leaked_roots:
    problems.append(f"~/.agents/skills leak still enabled: {name}")

shelf_enabled = [s["name"] for s in skills
                 if not s.get("disabled") and "grok-skill-shelf" in s["source"]["path"]]
off_pack = [n for n in shelf_enabled if n not in core]
for name in off_pack:
    problems.append(f"skill from an OFF shelf pack is enabled: {name}")

# The core shelf is a library, not a catalog: these are read on demand by the
# router and must stay disabled in the model-facing list.
shelf_on_demand = sorted(n for n in SHELF_CORE if n in enabled)
if shelf_core.is_dir() and shelf_on_demand:
    problems.append(f"shelf-core skills should stay on-demand (disabled): {shelf_on_demand}")

collisions = [s["name"] for s in skills if s.get("collidesWith") and s["name"] in core]
for name in collisions:
    problems.append(f"core skill name collides: {name}")

non_invocable = [s["name"] for s in skills if s["name"] in core and not s.get("userInvocable")]
for name in non_invocable:
    problems.append(f"core skill not user-invocable: {name}")

# The toggles must stay disable-model-invocation, i.e. slash-only. That flag is
# what keeps them out of the model-facing skill catalog: measured 2026-09-10 with
# `grok -p ... --output-format json`, disabling all 14 moved the prompt by ~2
# tokens, while 5 model-invocable core skills moved it by 463. Never "trim" them
# for token savings - there are none.
for name in sorted(TOGGLES):
    entry = by_name.get(name)
    if entry is None:
        continue
    path = pathlib.Path(entry["source"]["path"])
    head = path.read_text(encoding="utf-8", errors="replace").split("---")[1:2]
    if not head or "disable-model-invocation: true" not in head[0]:
        problems.append(f"toggle {name} is model-invocable; it would enter the prompt catalog")

print(f"enabled skills: {len(enabled)} (expected {len(expected)})")
print(f"  policy {len(enabled & POLICY)}/{len(POLICY)}"
      f" · toggles {len(enabled & TOGGLES)}/{len(TOGGLES)}"
      f" · bundled {len(enabled & BUNDLED)}/{len(BUNDLED)}"
      f" · user {len(enabled & user)}/{len(user)}")
if shelf_core.is_dir():
    print(f"  shelf-core on demand: {len(SHELF_CORE - enabled)}/{len(SHELF_CORE)} disabled")
print(f"total catalog entries: {len(skills)} (enabled + disabled)")

if problems:
    print("\nPROBLEMS:")
    for p in problems:
        print("  -", p)
    sys.exit(1)
print("CLEAN: catalog matches the sets in this file, toggles are slash-only")
