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
  pwsh -File $env:USERPROFILE\.grok\start-grok.ps1 -Design
  pwsh -File $env:USERPROFILE\.grok\start-grok.ps1 -Design -p "Use the pen.dev canvas for this brief"
  pwsh -File $env:USERPROFILE\.grok\start-grok.ps1 -Design -Inspo -p "Use the canvas and Inspo references"
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
# glm-flash seat (Z.ai PAYG) and the mem0 hosted MCP key: same rationale as
# DeepSeek - pull them from the User env so old terminals still work.
$null = Import-UserEnvVar -Name 'ZAI_API_KEY'
$null = Import-UserEnvVar -Name 'MEM0_API_KEY'

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

# The OpenCode Zen seats and their 8791 relay were removed 2026-09-10, and the
# xAI-hosted seats were retired 2026-10-17 (Grok Build balance exhausted; HTTP
# 402). Four seats now, all direct to their provider: deepseek-flash,
# deepseek-flash-high, deepseek-pro, glm-flash. OPENCODE_ZEN_API_KEY is unused.

# Always launch the real binary by absolute path — never resolve "grok" from PATH
# (PATH may point at the User\bin wrapper that re-enters this script).
$grok = Join-Path $env:USERPROFILE '.grok\bin\grok.exe'
if (-not (Test-Path -LiteralPath $grok)) {
    throw "grok.exe not found at $grok"
}

# --- default-model guard: begin ---
# Grok Build's TUI model switch (/model or the Ctrl+M picker) is a settings
# action: it changes the session model AND writes [models] default in
# config.toml (Action::SetDefaultModel; build 1.0.62). That turns a one-off
# seat change into the permanent default for every later session.
# This guard snapshots the default before the session and restores it when
# grok exits, so /model is effectively session-scoped while config.toml stays
# the source of truth. For a per-process seat with no write at all, launch:
#   start-grok.ps1 -m glm-flash      (the -m flag never writes config)
function Get-GrokDefaultModel {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text = [IO.File]::ReadAllText($Path)
    $m = [regex]::Match($text, '(?ms)^\[models\][ \t]*\r?\n(?:(?!^\[)[\s\S])*?^default[ \t]*=[ \t]*"([^"]*)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Restore-GrokDefaultModel {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Value
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $text = [IO.File]::ReadAllText($Path)
    $rx = [regex]'(?ms)(^\[models\][ \t]*\r?\n(?:(?!^\[)[\s\S])*?^default[ \t]*=[ \t]*")([^"]*)(")'
    $m = $rx.Match($text)
    if (-not $m.Success) { return $false }
    if ($m.Groups[2].Value -eq $Value) { return $true }
    $new = $rx.Replace($text, { param($mm) $mm.Groups[1].Value + $Value + $mm.Groups[3].Value }, 1)
    [IO.File]::WriteAllText($Path, $new)
    return $true
}
# --- default-model guard: end ---

$configPath = Join-Path $env:USERPROFILE '.grok\config.toml'
$defaultBefore = Get-GrokDefaultModel -Path $configPath

function Get-McpEnabled {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text = [IO.File]::ReadAllText($Path)
    $escaped = [regex]::Escape($Name)
    $m = [regex]::Match($text, "(?ms)\[mcp_servers\.$escaped\](.*?)(?=\r?\n\[|\z)")
    if (-not $m.Success) { return $null }
    $em = [regex]::Match($m.Groups[1].Value, '(?m)^\s*enabled\s*=\s*(true|false)\s*$')
    if (-not $em.Success) { return $null }
    return ($em.Groups[1].Value -eq 'true')
}

function Set-McpEnabled {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Enabled
    )
    $text = [IO.File]::ReadAllText($Path)
    $val = if ($Enabled) { 'true' } else { 'false' }
    $escaped = [regex]::Escape($Name)
    $rx = [regex]"(?ms)(\[mcp_servers\.$escaped\]\r?\n)(.*?)(?=\r?\n\[|\z)"
    $m = $rx.Match($text)
    if (-not $m.Success) { return $false }
    $body = [regex]::Replace($m.Groups[2].Value, '(?m)^\s*enabled\s*=\s*(true|false)\s*\r?\n?', '')
    $body = $body.TrimEnd() + "`r`nenabled = $val`r`n"
    $new = $text.Substring(0, $m.Index) + $m.Groups[1].Value + $body + $text.Substring($m.Index + $m.Length)
    [IO.File]::WriteAllText($Path, $new, (New-Object System.Text.UTF8Encoding $false))
    return $true
}

# Drift canary: the harness treats the templates as the source of truth, so a
# live default that differs from the lean template is flagged before launch.
$leanPath = Join-Path $env:USERPROFILE '.grok\config.lean.toml'
if ($defaultBefore -and (Test-Path -LiteralPath $leanPath)) {
    $leanDefault = Get-GrokDefaultModel -Path $leanPath
    if ($leanDefault -and ($leanDefault -ne $defaultBefore)) {
        Write-Warning "start-grok: live default '$defaultBefore' differs from the lean template '$leanDefault'. Run the verifier after this session."
    }
}

# Per-session args: extract -ResumeHandoff / -Design / -Inspo (harness
# switches) and leave the rest for grok. The context watcher runs only for
# interactive sessions.
$resume = $false
$design = $false
$inspo = $false
$forward = @()
foreach ($a in $args) {
    if ($a -eq '-ResumeHandoff') { $resume = $true }
    elseif ($a -eq '-Design') { $design = $true }
    elseif ($a -eq '-Inspo') { $inspo = $true }
    else { $forward += $a }
}
$headless = ($forward -contains '-p') -or ($forward -contains '--single') -or
            ($forward -contains '--prompt-file') -or ($forward -contains '--prompt-json')

$handoffPath = Join-Path $env:USERPROFILE '.grok\handoffs\.last-handoff'
if ($resume) {
    if (Test-Path -LiteralPath $handoffPath) {
        try { $h = Get-Content -LiteralPath $handoffPath -Raw | ConvertFrom-Json } catch { $h = $null }
        if ($h -and $h.path -and (Test-Path -LiteralPath $h.path)) {
            if ($headless) {
                Write-Host "start-grok: handoff at $($h.path) (headless: pass it in your prompt)" -ForegroundColor DarkGray
            } else {
                $prompt = "Read the handoff at $($h.path) and continue the work. Do not redo completed items. Re-read SPEC.md, DESIGN.md and AGENTS.md first."
                $forward = @($prompt) + $forward
            }
        } else {
            Write-Warning "start-grok: -ResumeHandoff given but no handoff file was found."
        }
    } else {
        Write-Warning "start-grok: -ResumeHandoff given but .last-handoff is missing."
    }
}

$watcher = $null
$pencilBefore = Get-McpEnabled -Path $configPath -Name 'pencil'
$inspoBefore = Get-McpEnabled -Path $configPath -Name 'inspo'

if ($null -ne $pencilBefore) {
    if ($design -and -not $pencilBefore) {
        if (Set-McpEnabled -Path $configPath -Name 'pencil' -Enabled $true) {
            Write-Host "start-grok: pencil MCP ON for this design session (restores off on exit)." -ForegroundColor DarkGray
        }
    } elseif (-not $design -and $pencilBefore) {
        if (Set-McpEnabled -Path $configPath -Name 'pencil' -Enabled $false) {
            Write-Host "start-grok: pencil MCP OFF for this session (use -Design for canvas work)." -ForegroundColor DarkGray
        }
    }
}

if ($null -ne $inspoBefore) {
    if ($inspo -and -not $inspoBefore) {
        if (Set-McpEnabled -Path $configPath -Name 'inspo' -Enabled $true) {
            Write-Host "start-grok: Inspo MCP ON for this session (restores off on exit)." -ForegroundColor DarkGray
        }
    } elseif (-not $inspo -and $inspoBefore) {
        if (Set-McpEnabled -Path $configPath -Name 'inspo' -Enabled $false) {
            Write-Host "start-grok: Inspo MCP OFF for this session (use -Inspo for references)." -ForegroundColor DarkGray
        }
    }
}

$watchScript = Join-Path $env:USERPROFILE '.grok\skills\skill-router\scripts\context-watch.ps1'
if (-not $headless -and (Test-Path -LiteralPath $watchScript)) {
    $quotedCwd = '"' + (Get-Location).Path + '"'
    $watcher = Start-Process -FilePath 'powershell' `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $watchScript, '-Cwd', $quotedCwd) `
        -PassThru -WindowStyle Hidden
}
$sessionStart = Get-Date

try {
    & $grok @forward
} finally {
    if ($watcher) { Stop-Process -Id $watcher.Id -Force -ErrorAction SilentlyContinue }
    if ($null -ne $pencilBefore -or $null -ne $inspoBefore) {
        foreach ($entry in @(
            @{ Name = 'pencil'; Before = $pencilBefore },
            @{ Name = 'inspo'; Before = $inspoBefore }
        )) {
            if ($null -eq $entry.Before) { continue }
            $now = Get-McpEnabled -Path $configPath -Name $entry.Name
            if ($now -ne $entry.Before) {
                if (Set-McpEnabled -Path $configPath -Name $entry.Name -Enabled $entry.Before) {
                    $state = if ($entry.Before) { 'on' } else { 'off' }
                    Write-Host "start-grok: restored $($entry.Name) MCP to $state." -ForegroundColor DarkGray
                }
            }
        }
    }
    if ($defaultBefore) {
        $defaultNow = Get-GrokDefaultModel -Path $configPath
        if ($defaultNow -and ($defaultNow -ne $defaultBefore)) {
            if (Restore-GrokDefaultModel -Path $configPath -Value $defaultBefore) {
                Write-Host "start-grok: restored [models] default to '$defaultBefore' (the session had switched it to '$defaultNow')." -ForegroundColor DarkGray
            }
        }
    }
    if (Test-Path -LiteralPath $handoffPath) {
        try { $h = Get-Content -LiteralPath $handoffPath -Raw | ConvertFrom-Json } catch { $h = $null }
        if ($h -and $h.path -and (Test-Path -LiteralPath $h.path) -and ([datetime]$h.created -ge $sessionStart)) {
            $leaf = Split-Path $h.path -Leaf
            Write-Host "start-grok: handoff written: $($h.path)" -ForegroundColor Yellow
            Write-Host "start-grok: in-session: /new, then /pull-handoff $leaf" -ForegroundColor Yellow
            Write-Host "start-grok: new process: powershell -File `"$env:USERPROFILE\.grok\start-grok.ps1`" -ResumeHandoff" -ForegroundColor Yellow
        }
    }
}
exit $LASTEXITCODE
