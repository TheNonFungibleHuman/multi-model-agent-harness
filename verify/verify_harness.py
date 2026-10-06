"""Verify the harness end state: configs, ports, shelf, skills, seats.

Edit the sets below when you change which seats or skills you keep.
POLICY_SKILLS and TOGGLE_SKILLS are the skills this repo installs.
SHELF_CORE is checked only when ~/grok-skill-shelf/core exists. Those packs
are third-party and are not included in this repo.
"""
import os
import pathlib
import socket
import sys
import tomllib

G = pathlib.Path.home() / ".grok"
SHELF = pathlib.Path.home() / "grok-skill-shelf"
FILES = ["config.toml", "config.lean.toml", "config.full.toml"]
BAD = []

EXPECTED_SEATS = {"deepseek-flash", "deepseek-flash-high", "grok-4.5", "grok-4.6"}
REMOVED_SEATS = {"deepseek-pro", "zen-deepseek-free", "zen-mimo", "big-pickle",
                 "zen-muse-spark-12", "zen-muse-spark-13",
                 "zen-ling-flash-fin", "zen-nemotron-lightning", "zen-nemotron-ultra",
                 "gemini-flash", "gemini-pro", "gemini-image", "gemini-36", "gemini-31-pro"}
RETIRED_PORTS = (8787, 8788, 8789, 8791)
POLICY_SKILLS = {
    "route", "delegate", "web-search", "capture-lesson", "handoff", "pull-handoff",
}
TOGGLE_SKILLS = {
    "shelf-core-on", "shelf-design-on", "shelf-extras-on", "shelf-firecrawl-on",
    "shelf-matt-on", "shelf-off", "shelf-status", "shelf-video-on",
    "mcp-design-on", "mcp-design-off", "mcp-design-status",
    "profile-full", "profile-lean", "profile-status",
}
# Third-party skills on the author's core shelf. Not shipped here.
SHELF_CORE = {
    "code-review", "diagnosing-bugs", "tdd", "codebase-design", "domain-modeling",
    "find-skills", "here-now", "resolving-merge-conflicts", "wizard", "writing-for-agents",
}
IGNORED_AGENT_SKILLS = {"code-review", "diagnosing-bugs", "find-skills", "here-now",
                        "resolving-merge-conflicts", "tdd"}

configs = {}
for name in FILES:
    path = G / name
    data = path.read_bytes()
    text = data.decode("utf-8")
    cfg = tomllib.loads(text)
    configs[name] = cfg
    print(name)
    print(f"   default={cfg['models']['default']}  effort={cfg['models']['default_reasoning_effort']}"
          f"  web_search={cfg['models']['web_search']}")
    print(f"   seats={sorted(cfg['model'])}")
    print(f"   subagents: plan={cfg['subagents']['models']['plan']} explore={cfg['subagents']['models']['explore']}")
    print(f"   mcp: exa={cfg['mcp_servers']['exa']['enabled']} paper={cfg['mcp_servers']['paper']['enabled']}"
          f"  open-design={cfg['mcp_servers']['open-design']['enabled']}")

    if b"\xc3\xa2\xe2\x82\xac" in data or b"\xef\xbf\xbd" in data:
        BAD.append(f"{name}: mojibake present")
    if b"\\r\n" in data:
        BAD.append(f"{name}: literal backslash-r at EOL")

    seats = set(cfg["model"])
    missing = EXPECTED_SEATS - seats
    extra = (seats - EXPECTED_SEATS) & REMOVED_SEATS
    if missing:
        BAD.append(f"{name}: missing seats {sorted(missing)}")
    if extra:
        BAD.append(f"{name}: dead seats still present {sorted(extra)}")

    # The auto-tuner owns these windows and moves them between its own bounds
    # (tuner.py WINDOW_FLOOR..WINDOW_CAP), so an exact value is not assertable:
    # the live config legitimately differs from the profiles, and a profile
    # switch re-applies the live values (token-ledger/carry_tuning.py).
    for seat, sc in cfg["model"].items():
        window = sc.get("context_window")
        if window is not None and not (131072 <= window <= 524288):
            BAD.append(f"{name}: {seat}.context_window={window} outside tuner bounds")

    ignored = cfg["skills"].get("ignore", [])
    for skill in IGNORED_AGENT_SKILLS:
        if f"~/.agents/skills/{skill}" not in ignored:
            BAD.append(f"{name}: skills.ignore missing ~/.agents/skills/{skill}")

# all three profiles must agree on the seat set and the default
seat_sets = {name: set(cfg["model"]) for name, cfg in configs.items()}
if len(set(map(frozenset, seat_sets.values()))) != 1:
    BAD.append(f"profiles disagree on seats: { {k: sorted(v) for k, v in seat_sets.items()} }")
defaults = {cfg["models"]["default"] for cfg in configs.values()}
if defaults != {"deepseek-flash"}:
    BAD.append(f"profiles disagree on default model: {defaults}")

print("\n-- retired ports --")
for port in RETIRED_PORTS:
    sock = socket.socket()
    sock.settimeout(1.0)
    try:
        sock.connect(("127.0.0.1", port))
        listening = True
    except OSError:
        listening = False
    finally:
        sock.close()
    print(f"   {port}: {'LISTENING  <-- problem' if listening else 'closed'}")
    if listening:
        BAD.append(f"port {port} still has a listener")

print("\n-- retired proxy pid files --")
for rel in ("zen-strip-proxy/proxy.pid", "deepseek-strip-proxy/proxy.pid",
            "gemini-inline-proxy/proxy.pid", "zen-relay/relay.pid"):
    pid_file = G / rel
    if pid_file.exists():
        print(f"   {rel}: STALE  <-- problem")
        BAD.append(f"stale pid file {rel}")
    else:
        print(f"   {rel}: absent")

# The zen relay existed only for the Muse seats; both are gone, so the folder goes.
if (G / "zen-relay").exists():
    print("   ~/.grok/zen-relay: STILL PRESENT  <-- problem")
    BAD.append("zen-relay folder still present")

print("\n-- skill shelf --")


def is_link(path):
    """True for symlinks and Windows directory junctions."""
    if os.path.islink(path):
        return True
    try:
        return os.path.isjunction(path)
    except AttributeError:
        return bool(getattr(os.lstat(path), "st_reparse_tag", 0))


skills_dir = G / "skills"
if not skills_dir.is_dir():
    BAD.append("~/.grok/skills missing")
else:
    links = {}
    for entry in sorted(skills_dir.iterdir()):
        if is_link(entry):
            target = pathlib.Path(os.path.realpath(entry))
            if "grok-skill-shelf" in str(target):
                links[entry.name] = target
    off_links = {n: t for n, t in links.items() if t.parent.name != "core"}
    if off_links:
        BAD.append(f"shelved packs still linked: {sorted(off_links)}")
    shelf_core = SHELF / "core"
    if shelf_core.is_dir():
        core_links = {n: t for n, t in links.items() if t.parent.name == "core"}
        expected = POLICY_SKILLS | SHELF_CORE
        print(f"   core junctions: {len(core_links)} (expected {len(expected)})")
        print(f"   off-pack junctions: {len(off_links)} (expected 0)")
        missing_core = expected - set(core_links)
        if missing_core:
            BAD.append(f"core skills not linked: {sorted(missing_core)}")
        on_disk = {p.name for p in shelf_core.iterdir() if p.is_dir() and not is_link(p)}
        if on_disk != expected:
            BAD.append(f"core pack contents differ: {sorted(on_disk ^ expected)}")
    else:
        shipped = POLICY_SKILLS | TOGGLE_SKILLS
        missing = sorted(n for n in shipped if not (skills_dir / n).exists())
        print(f"   no core shelf; shipped skills present: {len(shipped) - len(missing)}/{len(shipped)}")
        print(f"   off-pack junctions: {len(off_links)} (expected 0)")
        if missing:
            BAD.append(f"shipped skills missing: {missing}")

print()
if BAD:
    print("PROBLEMS:")
    for b in BAD:
        print("  -", b)
    sys.exit(1)
print("CLEAN: configs parse and agree, no dead seats, retired ports closed, skills in place")
