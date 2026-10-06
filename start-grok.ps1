#Requires -Version 5.1
<#
.SYNOPSIS
  Start Grok with Windows User env API keys loaded into this process.

.DESCRIPTION
  DeepSeek seats use env_key in config.toml. If Grok is started from a
  host that never inherited User env (old terminal, some shortcuts), those vars
  are empty → 401 on the provider → false grok.com re-login loop.
  This script always pulls DEEPSEEK_API_KEY from the User environment before
  launching grok.exe. Keys are never printed. Gemini seats are unplugged.

.EXAMPLE
  pwsh -File $env:USERPROFILE\.grok\start-grok.ps1
  pwsh -File $env:USERPROFILE\.grok\start-grok.ps1 -p "ping"
#>

$ErrorActionPreference = 'Stop'

function Import-UserEnvVar {
    param([Parameter(Mandatory)][string]$Name)
    $val = [Environment]::GetEnvironmentVariable($Name, 'User')
    if ([string]::IsNullOrWhiteSpace($val)) {
        $val = [Environment]::GetEnvironmentVariable($Name, 'Machine')
    }
    if (-not [string]::IsNullOrWhiteSpace($val)) {
        Set-Item -Path "Env:$Name" -Value $val
        return $val.Length
    }
    return 0
}

$deepseekLen = Import-UserEnvVar -Name 'DEEPSEEK_API_KEY'
# Optional xAI key if you use API-key auth instead of browser login
$null = Import-UserEnvVar -Name 'XAI_API_KEY'
$null = Import-UserEnvVar -Name 'GROK_CODE_XAI_API_KEY'

# Enable the web_fetch tool (disabled by default unless GROK_WEB_FETCH=1).
$null = Import-UserEnvVar -Name 'GROK_WEB_FETCH'
if (-not $env:GROK_WEB_FETCH) { $env:GROK_WEB_FETCH = '1' }

Write-Host "start-grok: DEEPSEEK_API_KEY len=$deepseekLen" -ForegroundColor DarkGray
if ($deepseekLen -eq 0) {
    Write-Warning "DEEPSEEK_API_KEY is not set in User/Machine env. DeepSeek seats will fail or re-auth loop. Set with [Environment]::SetEnvironmentVariable('DEEPSEEK_API_KEY','…','User') then re-run."
}

# DeepSeek V4.1 Flash talks to https://api.deepseek.com directly (native multimodal).
# The old 8787 strip-proxy is retired — do not start it.

# Gemini seats are unplugged (no [model.gemini-*], no 8788 proxy).

# The OpenCode Zen seats and their 8791 relay were removed 2026-09-10. Four seats
# now, all direct to their provider: deepseek-flash, deepseek-flash-high,
# grok-4.5, grok-4.6. OPENCODE_ZEN_API_KEY is no longer read by anything.

# Always launch the real binary by absolute path — never resolve "grok" from PATH
# (PATH may point at the User\bin wrapper that re-enters this script).
$grok = Join-Path $env:USERPROFILE '.grok\bin\grok.exe'
if (-not (Test-Path -LiteralPath $grok)) {
    throw "grok.exe not found at $grok"
}

# Forward all remaining args to Grok (e.g. -p, paths)
& $grok @args
exit $LASTEXITCODE
