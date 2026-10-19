# Windows Sandbox recipe

The harness guard (`isolation-guard.py`) is a **policy boundary**, not a kernel
sandbox. It blocks direct tool writes outside the workspace and obvious
destructive shell commands, but allowed child processes are not confined.

Use Windows Sandbox when the repository or the instructions are untrusted.

## Status on this machine

- Windows 11 Pro.
- Windows Sandbox is **not enabled** (`C:\Windows\System32\WindowsSandbox.exe`
  is absent as of 2026-10-18).
- Enabling it needs an elevated PowerShell and a reboot.

## One-time setup

```powershell
# In an elevated PowerShell:
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.grok\sandbox\enable-windows-sandbox.ps1"
# Reboot, then verify:
Get-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM
```

## Run a repo

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.grok\sandbox\run-in-sandbox.ps1" -Repo C:\path\to\repo
```

Defaults:

| Setting | Default | Why |
|---|---|---|
| Host folder | mapped **read-only** at `C:\repo` | guest writes never touch the host |
| Guest workdir | `C:\work` (robocopy of `C:\repo`) | disposable copy |
| Networking | **disabled** | no exfiltration path |
| vGPU | disabled | smaller attack surface |

Switches:

- `-AllowNetwork` — enable guest networking (needed for package installs).
- `-ReadWrite` — junction the host repo directly (changes persist; use only for
  trusted code).
- `-GenerateOnly` — write the `.wsb` and entry script without launching; useful
  for review or on a machine where Sandbox is not enabled yet.

## What the guest looks like

1. Windows Sandbox boots as `WDAGUtilityAccount`.
2. `C:\entry\start.ps1` copies `C:\repo` to `C:\work` and opens PowerShell there.
3. The host repo stays read-only at `C:\repo`.
4. Close the Sandbox window to discard everything.

## Limits

- Windows Sandbox is Pro/Enterprise/Education only; this host qualifies.
- It is still Windows: a kernel exploit can escape, but the blast radius is a
  disposable VM, not your real profile.
- No host `~/.grok` state is mapped. Do not copy API keys or `auth.json` into the
  guest; re-authenticate there if the agent needs a provider.
- If you need a persistent, snapshottable environment, use a Hyper-V VM instead.

## Verify the recipe without Sandbox enabled

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.grok\sandbox\run-in-sandbox.ps1" -Repo . -GenerateOnly
```

Inspect the printed `.wsb` path: it should map the repo read-only, disable
networking, and point `LogonCommand` at `C:\entry\start.ps1`.
