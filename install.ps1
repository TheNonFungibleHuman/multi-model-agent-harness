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
            # rmdir drops the junction and leaves the directory it points at.
            & cmd.exe /c "rmdir `"$to`""
            if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath $to)) {
                throw "Could not remove the junction at $to"
            }
        } else {
            Remove-Item -LiteralPath $to -Recurse -Force
        }
    }
    Copy-Item -LiteralPath $from -Destination $to -Recurse -Force
}

foreach ($name in 'switch-profile.ps1', 'start-grok.ps1', 'start-grok.cmd', 'toggle-design-mcp.ps1', 'config.lean.toml', 'config.full.toml') {
    Copy-Item -LiteralPath (Join-Path $repo $name) -Destination (Join-Path $dest $name) -Force
}

$shelfDir = Join-Path $env:USERPROFILE 'grok-skill-shelf'
New-Item -ItemType Directory -Force -Path $shelfDir | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'shelf.ps1') -Destination (Join-Path $shelfDir 'shelf.ps1') -Force

New-Item -ItemType Directory -Force -Path (Join-Path $dest 'rules') | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'rules\00-token-efficiency.md') -Destination (Join-Path $dest 'rules\00-token-efficiency.md') -Force

$ledger = Join-Path $dest 'token-ledger'
New-Item -ItemType Directory -Force -Path $ledger | Out-Null
foreach ($name in 'ledger.py', 'tuner.py', 'carry_tuning.py', 'overrides.toml', 'README.md', 'register-startup.ps1', 'unregister-startup.ps1', 'report.ps1', 'start.ps1', 'run-hidden.vbs') {
    Copy-Item -LiteralPath (Join-Path $repo "token-ledger\$name") -Destination (Join-Path $ledger $name) -Force
}

$verify = Join-Path $dest 'verify'
New-Item -ItemType Directory -Force -Path $verify | Out-Null
foreach ($name in 'verify_harness.py', 'verify_skills.py', 'test_switch_carry.py') {
    Copy-Item -LiteralPath (Join-Path $repo "verify\$name") -Destination (Join-Path $verify $name) -Force
}

New-Item -ItemType Directory -Force -Path (Join-Path $dest 'skills') | Out-Null
Get-ChildItem -LiteralPath (Join-Path $repo 'skills') -Directory | ForEach-Object {
    Install-Skill $_.Name
}

$configDest = Join-Path $dest 'config.toml'
if ((-not (Test-Path -LiteralPath $configDest)) -or $ForceConfig) {
    Copy-Item -LiteralPath (Join-Path $repo 'config.toml') -Destination $configDest -Force
    Write-Host "Wrote $configDest"
} else {
    Write-Host "Kept the existing config.toml."
    Write-Host "Re-run with -ForceConfig to replace it with this repo's starter (a copy of config.lean.toml)."
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
