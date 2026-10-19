#Requires -Version 5.1
<#
.SYNOPSIS
  Integrity canary for the Grok harness: hashes hooks, rules and gate scripts,
  reports drift, and can register itself as a daily scheduled task.

.DESCRIPTION
  The harness is only as trustworthy as its gates. This canary records a
  baseline of the files that enforce policy and tells you when one changes
  without an explicit baseline update.

  Scope (deliberately small, so it stays readable):
    hooks/*.json
    rules/*.md
    skills/skill-router/scripts/{isolation-guard,anti-slop-stop,evidence-gate}.py
    skills/skill-router/scripts/impeccable-ui-hook.py
    skills/skill-router/scripts/{design-gate,preview-shot}.ps1
    skills/skill-router/scripts/cdp-shot.mjs
    start-grok.ps1
    verify/{verify_harness,verify_skills}.py
    config.lean.toml, config.full.toml   (templates only; live config.toml is
                                          legitimately edited by profiles/tuner)

  Usage:
    powershell -NoProfile -File $env:USERPROFILE\.grok\verify\integrity-canary.ps1
    powershell -NoProfile -File $env:USERPROFILE\.grok\verify\integrity-canary.ps1 -Update
    powershell -NoProfile -File $env:USERPROFILE\.grok\verify\integrity-canary.ps1 -Install
    powershell -NoProfile -File $env:USERPROFILE\.grok\verify\integrity-canary.ps1 -Uninstall
    powershell -NoProfile -File $env:USERPROFILE\.grok\verify\integrity-canary.ps1 -Show

  Exit codes: 0 clean, 1 drift, 2 baseline missing, 3 setup error.
#>

[CmdletBinding()]
param(
  [switch]$Update,
  [switch]$Install,
  [switch]$Uninstall,
  [switch]$Show,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

$Root       = Join-Path $env:USERPROFILE '.grok'
$VerifyDir  = Join-Path $Root 'verify'
$Baseline   = Join-Path $VerifyDir 'integrity-baseline.json'
$AlertFile  = Join-Path $VerifyDir 'INTEGRITY-ALERT.txt'
$LogFile    = Join-Path $Root 'logs\canary.log'
$TaskName   = 'GrokHarnessIntegrityCanary'

$Targets = @(
  'hooks\*.json',
  'rules\*.md',
  'skills\skill-router\scripts\anti-slop-stop.py',
  'skills\skill-router\scripts\evidence-gate.py',
  'skills\skill-router\scripts\impeccable-ui-hook.py',
  'skills\skill-router\scripts\design-lane.ps1',
  'skills\skill-router\scripts\preview-shot.ps1',
  'skills\skill-router\scripts\cdp-shot.mjs',
  'start-grok.ps1',
  'toggle-design-mcp.ps1',
  'verify\verify_harness.py',
  'verify\verify_skills.py',
  'config.lean.toml',
  'config.full.toml'
)

function Write-CanaryLog {
  param([string]$Message)
  $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
  $dir = Split-Path -Parent $LogFile
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  # A scheduled run can overlap a manual run, and AV/indexers can hold the log
  # briefly. Retry rather than failing the whole canary on a transient lock.
  $written = $false
  for ($i = 0; $i -lt 6 -and -not $written; $i++) {
    try {
      Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
      $written = $true
    } catch {
      Start-Sleep -Milliseconds 250
    }
  }
  if (-not $Quiet) { Write-Host $Message }
}

function Get-CriticalFiles {
  $seen = @{}
  $files = New-Object System.Collections.Generic.List[object]
  foreach ($pattern in $Targets) {
    $full = Join-Path $Root $pattern
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($f in Get-ChildItem -LiteralPath $dir -Filter (Split-Path -Leaf $full) -File -ErrorAction SilentlyContinue) {
      $rel = $f.FullName.Substring($Root.Length).TrimStart('\')
      if ($seen.ContainsKey($rel)) { continue }
      $seen[$rel] = $true
      $files.Add([pscustomobject]@{
        Relative = $rel
        FullName = $f.FullName
        Sha256   = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
      })
    }
  }
  return $files
}

function New-Baseline {
  $files = Get-CriticalFiles
  $map = [ordered]@{}
  foreach ($f in ($files | Sort-Object Relative)) { $map[$f.Relative] = $f.Sha256 }
  $obj = [pscustomobject]@{
    createdAt = (Get-Date).ToString('o')
    root      = $Root
    fileCount = $map.Count
    files     = $map
  }
  if (-not (Test-Path -LiteralPath $VerifyDir)) { New-Item -ItemType Directory -Path $VerifyDir -Force | Out-Null }
  $obj | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Baseline -Encoding UTF8
  if (Test-Path -LiteralPath $AlertFile) { Remove-Item -LiteralPath $AlertFile -Force }
  Write-CanaryLog ("baseline written: {0} file(s) -> {1}" -f $map.Count, $Baseline)
}

function Show-Baseline {
  if (-not (Test-Path -LiteralPath $Baseline)) { throw "no baseline at $Baseline" }
  $b = Get-Content -LiteralPath $Baseline -Raw | ConvertFrom-Json
  Write-Host "Baseline: $($b.createdAt)  ($($b.fileCount) files)"
  $b.files.PSObject.Properties | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0}  {1}" -f $_.Value.Substring(0, 12), $_.Name)
  }
}

function Show-Alert {
  param([string[]]$Lines)
  $body = @(
    'Grok harness integrity drift detected.',
    "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '',
    'If you did not intentionally change a hook, rule or gate, inspect these:',
    ''
  ) + $Lines + @(
    '',
    "Baseline: $Baseline",
    "Log:      $LogFile",
    'Re-baseline only after reviewing the change:',
    "  powershell -NoProfile -File `"$PSCommandPath`" -Update"
  )
  $body | Set-Content -LiteralPath $AlertFile -Encoding UTF8

  try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $icon = New-Object System.Windows.Forms.NotifyIcon
    $icon.Icon = [System.Drawing.SystemIcons]::Warning
    $icon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning
    $icon.BalloonTipTitle = 'Grok harness integrity alert'
    $icon.BalloonTipText = "Hook/rule/gate drift detected. See $AlertFile"
    $icon.Visible = $true
    $icon.ShowBalloonTip(15000)
    Start-Sleep -Seconds 6
    $icon.Dispose()
  } catch {
    # Toast is best-effort; the alert file and log are the durable signal.
  }
}

function Test-Baseline {
  if (-not (Test-Path -LiteralPath $Baseline)) {
    Write-CanaryLog 'baseline missing; run with -Update first'
    return 2
  }
  $b = Get-Content -LiteralPath $Baseline -Raw | ConvertFrom-Json
  $expected = @{}
  foreach ($p in $b.files.PSObject.Properties) { $expected[$p.Name] = $p.Value }

  $actual = @{}
  foreach ($f in Get-CriticalFiles) { $actual[$f.Relative] = $f.Sha256 }

  $changed = @()
  $missing = @()
  $added   = @()
  foreach ($k in ($expected.Keys | Sort-Object)) {
    if (-not $actual.ContainsKey($k)) { $missing += $k }
    elseif ($actual[$k] -ne $expected[$k]) { $changed += $k }
  }
  foreach ($k in ($actual.Keys | Sort-Object)) {
    if (-not $expected.ContainsKey($k)) { $added += $k }
  }

  if (-not ($changed.Count -or $missing.Count -or $added.Count)) {
    Write-CanaryLog ("clean: {0} file(s) match baseline" -f $actual.Count)
    if (Test-Path -LiteralPath $AlertFile) { Remove-Item -LiteralPath $AlertFile -Force }
    return 0
  }

  $lines = @()
  foreach ($k in $changed) { $lines += "CHANGED  $k" }
  foreach ($k in $missing) { $lines += "MISSING  $k" }
  foreach ($k in $added)   { $lines += "ADDED    $k" }
  foreach ($l in $lines) { Write-CanaryLog $l }
  Write-CanaryLog ("DRIFT: {0} changed, {1} missing, {2} added" -f $changed.Count, $missing.Count, $added.Count)
  Show-Alert -Lines $lines
  return 1
}

function Install-Task {
  $script = $PSCommandPath
  if (-not $script) { throw 'cannot resolve script path' }
  $tr = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Quiet' -f $script
  schtasks.exe /Create /TN $TaskName /SC DAILY /ST 09:00 /F /TR $tr | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "schtasks failed with $LASTEXITCODE" }
  Write-CanaryLog ("scheduled task installed: {0} (daily 09:00)" -f $TaskName)
  Write-Host "Installed scheduled task '$TaskName' (daily 09:00)."
  Write-Host "Run now:  schtasks /Run /TN $TaskName"
}

function Uninstall-Task {
  schtasks.exe /Delete /TN $TaskName /F 2>$null | Out-Null
  Write-CanaryLog ("scheduled task removed: {0}" -f $TaskName)
  Write-Host "Removed scheduled task '$TaskName' (if it existed)."
}

try {
  if ($Update)    { New-Baseline; exit 0 }
  if ($Show)      { Show-Baseline; exit 0 }
  if ($Install)   { Install-Task; exit 0 }
  if ($Uninstall) { Uninstall-Task; exit 0 }
  exit (Test-Baseline)
} catch {
  Write-CanaryLog ("ERROR: {0}" -f $_.Exception.Message)
  exit 3
}
