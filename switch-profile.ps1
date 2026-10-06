# Switch Grok config profile: lean (fewer skills) or full (everything).
# Usage (Windows PowerShell or pwsh):
#   powershell -File $env:USERPROFILE\.grok\switch-profile.ps1 lean
#   powershell -File $env:USERPROFILE\.grok\switch-profile.ps1 full
#   powershell -File $env:USERPROFILE\.grok\switch-profile.ps1   # prints which is active

param(
  [Parameter(Position = 0)]
  [ValidateSet("lean", "full", "")]
  [string]$ProfileName = ""
)

$grok = Join-Path $env:USERPROFILE ".grok"
$active = Join-Path $grok "config.toml"
$lean = Join-Path $grok "config.lean.toml"
$full = Join-Path $grok "config.full.toml"

function Get-ProfileFingerprint {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $null }
  return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash
}

function Show-Status {
  $a = Get-ProfileFingerprint $active
  $l = Get-ProfileFingerprint $lean
  $f = Get-ProfileFingerprint $full
  if ($null -eq $a) {
    Write-Host "No active config.toml found at $active"
    return
  }
  if ($a -eq $l) {
    Write-Host "Active profile: LEAN  ($active matches config.lean.toml)"
  }
  elseif ($a -eq $f) {
    Write-Host "Active profile: FULL  ($active matches config.full.toml)"
  }
  else {
    Write-Host "Active profile: CUSTOM  (config.toml does not match lean or full)"
    Write-Host "  Edit config.toml, or re-run: switch-profile.ps1 lean|full"
  }
  Write-Host ""
  Show-ReloadGuidance
}

# Print the mid-session reload guidance shared by status and switch paths.
function Show-ReloadGuidance {
  Write-Host "Apply NOW - no restart needed for the design MCP:"
  Write-Host "  In the running Grok TUI run:  /mcps   then press  r"
  Write-Host "  That re-reads config.toml, so the design MCP (paper/open-design) toggle"
  Write-Host "  goes live immediately. (Or toggle a server directly with Space in /mcps.)"
  Write-Host ""
  Write-Host "Next session start (skill catalog):"
  Write-Host "  The lean/full [skills] disabled + vendor-scan trim is read at startup, so the"
  Write-Host "  skill LIST refresh still wants a new session. Skill FILES on disk do hot-reload."
  Write-Host ""
  Write-Host "Optional full refresh: quit Grok and start a new session.  Check: grok inspect"
}

if ($ProfileName -eq "") {
  Show-Status
  exit 0
}

$src = if ($ProfileName -eq "lean") { $lean } else { $full }
if (-not (Test-Path $src)) {
  Write-Error "Missing profile file: $src"
  exit 1
}

# Install the profile, then re-apply the auto-tuner's live values on top: the
# tuner writes only config.toml, so a plain copy would silently revert every
# context_window / reasoning-effort / MCP decision it has made (see
# token-ledger/carry_tuning.py).
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) { $pythonCmd = Get-Command py -ErrorAction SilentlyContinue }
$carry = Join-Path $grok "token-ledger\carry_tuning.py"

$switched = $false
if ($pythonCmd -and (Test-Path $carry)) {
  & $pythonCmd.Source $carry --template $src
  if ($LASTEXITCODE -eq 0) {
    $switched = $true
  } else {
    Write-Warning "carry_tuning.py failed (exit $LASTEXITCODE); falling back to a plain copy."
  }
} else {
  Write-Warning "python or carry_tuning.py not found; falling back to a plain copy (tuner values will be lost)."
}
if (-not $switched) {
  Copy-Item -Path $src -Destination $active -Force
}

Write-Host "Switched to $ProfileName profile."
Write-Host "  Source: $src"
Write-Host "  Active: $active"
Write-Host ""
Show-Status
