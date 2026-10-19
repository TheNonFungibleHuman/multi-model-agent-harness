#Requires -Version 5.1
<#
.SYNOPSIS
  Copy this repo onto an installed Grok Build.

.DESCRIPTION
  The clone is the source of truth. Re-run this after you edit it.
  Copies the harness layer into %USERPROFILE%\.grok and shelf.ps1 into
  %USERPROFILE%\grok-skill-shelf.

  Leaves auth.json, sessions, logs, the Grok binary, and token-ledger data
  files (usage.jsonl, session_stats.jsonl, changes.log) where they are.
  Leaves an existing config.toml unless -ForceConfig is passed.
  config.lean.toml and config.full.toml are always updated from this repo.
  Pencil and Inspo MCPs are off by default; use -Design / -Inspo for a session.
  Skill names already linked from the shelf are left alone, and the shelf's
  core copies of the six policy skills are refreshed from skills\.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -ForceConfig
#>
param([switch]$ForceConfig)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$dest = Join-Path $env:USERPROFILE '.grok'
$grokExe = Join-Path $dest 'bin\grok.exe'

if (-not (Test-Path -LiteralPath $grokExe)) {
    throw "Grok Build is not installed at $grokExe. Install it from https://x.ai/cli and run this again."
}

function Install-Skill([string]$Name) {
    $from = Join-Path $repo "skills\$Name"
    $to = Join-Path $dest "skills\$Name"
    if (Test-Path -LiteralPath $to) {
        $item = Get-Item -LiteralPath $to -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            # Shelf-owned junction: leave it alone. shelf.ps1 links these names into
            # the shelf packs; replacing a junction with a real folder makes
            # Enable-Pack skip the name and trips the core-junction checks.
            Write-Host "Kept shelf junction: $Name"
            return
        } else {
            Remove-Item -LiteralPath $to -Recurse -Force
        }
    }
    Copy-Item -LiteralPath $from -Destination $to -Recurse -Force
}

foreach ($name in 'switch-profile.ps1', 'start-grok.ps1', 'start-grok.cmd', 'toggle-design-mcp.ps1', 'config.lean.toml', 'config.full.toml') {
    Copy-Item -LiteralPath (Join-Path $repo $name) -Destination (Join-Path $dest $name) -Force
}

# Pencil and Inspo are disabled in the templates; enable per session with
# start-grok.ps1 -Design / -Inspo.

$shelfDir = Join-Path $env:USERPROFILE 'grok-skill-shelf'
New-Item -ItemType Directory -Force -Path $shelfDir | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'shelf.ps1') -Destination (Join-Path $shelfDir 'shelf.ps1') -Force

New-Item -ItemType Directory -Force -Path (Join-Path $dest 'rules') | Out-Null
Get-ChildItem -LiteralPath (Join-Path $repo 'rules') -File -Filter '*.md' | ForEach-Object {
    $target = Join-Path $dest "rules\$($_.Name)"
    # 03-lessons.md is generated from the live lessons file; never overwrite it.
    if ($_.Name -eq '03-lessons.md' -and (Test-Path -LiteralPath $target)) { return }
    Copy-Item -LiteralPath $_.FullName -Destination $target -Force
}

$ledger = Join-Path $dest 'token-ledger'
New-Item -ItemType Directory -Force -Path $ledger | Out-Null
foreach ($name in 'ledger.py', 'tuner.py', 'carry_tuning.py', 'overrides.toml', 'README.md', 'register-startup.ps1', 'unregister-startup.ps1', 'report.ps1', 'start.ps1', 'run-hidden.vbs') {
    Copy-Item -LiteralPath (Join-Path $repo "token-ledger\$name") -Destination (Join-Path $ledger $name) -Force
}

$verify = Join-Path $dest 'verify'
New-Item -ItemType Directory -Force -Path $verify | Out-Null
foreach ($name in 'verify_harness.py', 'verify_skills.py', 'test_switch_carry.py', 'integrity-canary.ps1') {
    Copy-Item -LiteralPath (Join-Path $repo "verify\$name") -Destination (Join-Path $verify $name) -Force
}

# Hooks and the Windows Sandbox recipe are part of the harness. The canary
# baseline is local state and is never installed from the repo.
New-Item -ItemType Directory -Force -Path (Join-Path $dest 'hooks') | Out-Null
Get-ChildItem -LiteralPath (Join-Path $repo 'hooks') -File -Filter '*.json' | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest "hooks\$($_.Name)") -Force
}
if (Test-Path -LiteralPath (Join-Path $repo 'sandbox')) {
    Copy-Item -LiteralPath (Join-Path $repo 'sandbox') -Destination (Join-Path $dest 'sandbox') -Recurse -Force
}

New-Item -ItemType Directory -Force -Path (Join-Path $dest 'skills') | Out-Null
Get-ChildItem -LiteralPath (Join-Path $repo 'skills') -Directory | ForEach-Object {
    Install-Skill $_.Name
}

# On a machine with a core shelf pack, the six policy skills are junctions into
# ~/grok-skill-shelf/core. This repo owns their content, so refresh those copies
# too; otherwise policy edits would never reach the live catalog.
$shelfCore = Join-Path $env:USERPROFILE 'grok-skill-shelf\core'
if (Test-Path -LiteralPath $shelfCore) {
    foreach ($name in 'route', 'delegate', 'web-search', 'capture-lesson', 'handoff', 'pull-handoff') {
        $coreDir = Join-Path $shelfCore $name
        if (Test-Path -LiteralPath $coreDir) {
            Copy-Item -Path (Join-Path $repo "skills\$name\*") -Destination $coreDir -Recurse -Force
            Write-Host "Refreshed shelf core: $name"
        }
    }
}

$configDest = Join-Path $dest 'config.toml'
if ((-not (Test-Path -LiteralPath $configDest)) -or $ForceConfig) {
    Copy-Item -LiteralPath (Join-Path $repo 'config.toml') -Destination $configDest -Force
    Write-Host "Wrote $configDest"
} else {
    Write-Host "Kept the existing config.toml."
    Write-Host "Re-run with -ForceConfig to replace it with this repo's starter (a copy of config.lean.toml)."
}

# Regenerate the always-loaded lessons digest from the live lessons log.
$digest = Join-Path $dest 'skills\skill-router\scripts\lessons-digest.py'
if (Test-Path -LiteralPath $digest) {
    try { & python $digest | Out-Null } catch { Write-Warning "Lessons digest failed: $_" }
}

Write-Host ""
Write-Host "Installed into $dest"
Write-Host "Set DEEPSEEK_API_KEY in your user environment, then start with:"
Write-Host "  powershell -File `"$dest\start-grok.ps1`""
Write-Host "Check the install:"
Write-Host "  python `"$verify\verify_harness.py`""
Write-Host "  python `"$verify\verify_skills.py`""
Write-Host "Optional, to run the ledger and tuner every 15 minutes:"
Write-Host "  powershell -File `"$ledger\register-startup.ps1`""
