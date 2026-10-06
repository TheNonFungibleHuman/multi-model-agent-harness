"""End-to-end test: a profile switch must not discard the auto-tuner's values.

Writes a simulated "tuned" state (a reasoning effort and one seat window that
differ from the template) into the live config.toml, runs the real
switch-profile.ps1, asserts the tuned values survived the switch, then restores
the original config byte-for-byte.

This deliberately touches the live config, so run it when nothing else is writing
(config.toml is restored in a finally block even if an assertion fails).
Expectations are derived from the current config rather than hard-coded, so the
test keeps working as the tuner moves values around.
"""
import pathlib
import re
import subprocess
import tomllib

G = pathlib.Path.home() / ".grok"
CONFIG = G / "config.toml"
TEMPLATE = G / "config.lean.toml"
SWITCH = G / "switch-profile.ps1"
EFFORTS = ("low", "medium", "high", "xhigh")


def load(path):
    with open(path, "rb") as fh:
        return tomllib.load(fh)


def set_in_section(text, header, key, rendered):
    """Replace `key = ...` with `key = rendered` inside [header]."""
    start = text.index(f"[{header}]")
    nxt = text.find("\n[", start)
    end = len(text) if nxt == -1 else nxt + 1
    body, count = re.subn(rf"(?m)^{re.escape(key)}\s*=\s*.*$",
                          f"{key} = {rendered}", text[start:end], count=1)
    assert count == 1, f"{key} not found in [{header}]"
    return text[:start] + body + text[end:]


original = CONFIG.read_bytes()
text = original.decode("utf-8")
tpl = load(TEMPLATE)
backups_before = set(G.glob("config.toml.bak-switch-*"))
failures = []

try:
    tpl_effort = tpl["models"]["default_reasoning_effort"]
    tuned_effort = next(e for e in EFFORTS if e != tpl_effort)

    seat = next(s for s, v in tpl["model"].items() if "context_window" in v)
    tpl_window = tpl["model"][seat]["context_window"]
    tuned_window = tpl_window + 65536

    sim = set_in_section(text, "models", "default_reasoning_effort", f'"{tuned_effort}"')
    sim = set_in_section(sim, f"model.{seat}", "context_window", str(tuned_window))
    CONFIG.write_text(sim, encoding="utf-8", newline="\n")
    sim_parsed = tomllib.loads(sim)
    print(f"simulated tuner state: effort={tuned_effort}, [{seat}].context_window={tuned_window}")

    proc = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                           str(SWITCH), "lean"],
                          capture_output=True, text=True, encoding="utf-8", errors="replace")
    print("--- switch-profile.ps1 lean ---")
    print(proc.stdout.strip()[:900])
    if proc.stderr.strip():
        print("stderr:", proc.stderr.strip()[:400])

    after_text = CONFIG.read_text(encoding="utf-8")
    after = tomllib.loads(after_text)
    other_seats = {
        s: after["model"][s]["context_window"]
        for s in tpl["model"] if "context_window" in tpl["model"][s] and s != seat
    }
    sim_other = {
        s: sim_parsed["model"][s]["context_window"]
        for s in tpl["model"] if "context_window" in tpl["model"][s] and s != seat
    }
    checks = {
        "tuned reasoning effort survived": after["models"]["default_reasoning_effort"] == tuned_effort,
        f"tuned [{seat}] window survived": after["model"][seat]["context_window"] == tuned_window,
        "untouched seats kept the active (not template) window": other_seats == sim_other,
        "switch wrote a backup": bool(set(G.glob("config.toml.bak-switch-*")) - backups_before),
        "no literal backslash-r escapes": "\\r\n" not in after_text,
    }
    print("--- checks ---")
    for name, ok in checks.items():
        print(f"  {'PASS' if ok else 'FAIL'}  {name}")
    failures = [n for n, ok in checks.items() if not ok]
finally:
    CONFIG.write_bytes(original)
    restored = CONFIG.read_bytes() == original
    print(f"  {'PASS' if restored else 'FAIL'}  pre-test config restored byte-for-byte")
    if not restored:
        failures.append("restore")
    for stray in set(G.glob("config.toml.bak-switch-*")) - backups_before:
        stray.unlink()

print(f"\n{len(failures)} failure(s)" if failures else "\nCLEAN: profile switch preserves tuner values")
raise SystemExit(1 if failures else 0)
