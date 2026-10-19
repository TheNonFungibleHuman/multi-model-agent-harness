#Requires -Version 5.1
<#
.SYNOPSIS
  Watch the active Grok session's context and write a handoff at a threshold.
.DESCRIPTION
  Started by start-grok.ps1 for interactive sessions. Reads the newest primary
  session's signals.json (contextWindowUsage) and, at -Threshold percent,
  writes a handoff to ~/.grok/handoffs and raises a Windows toast telling the
  user to run /new and then /pull-handoff. It keeps running across /new and
  reminds the new session to load the handoff.
.EXAMPLE
  .\context-watch.ps1 -Cwd C:\Users\User\my-project -Threshold 70
#>
param(
  [string]$Cwd = (Get-Location).Path,
  [int]$Threshold = 70,
  [int]$PollSeconds = 5,
  [int]$MaxHours = 12,
  [string]$SessionsRoot = (Join-Path $env:USERPROFILE ".grok\sessions"),
  [string]$HandoffsRoot = (Join-Path $env:USERPROFILE ".grok\handoffs"),
  [string]$LogFile = "",
  [switch]$Once
)

$ErrorActionPreference = "Stop"
$deadline = (Get-Date).AddHours($MaxHours)
New-Item -ItemType Directory -Force -Path $HandoffsRoot | Out-Null
$stateDir = Join-Path $HandoffsRoot ".state"
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$lastHandoffMarker = Join-Path $HandoffsRoot ".last-handoff"

$encoded = [Uri]::EscapeDataString($Cwd)
$sessionDir = Join-Path $SessionsRoot $encoded

function Write-Log([string]$Message) {
  if ($LogFile) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
  }
}

function Get-NewestSession {
  if (-not (Test-Path -LiteralPath $sessionDir)) { return $null }
  Get-ChildItem -LiteralPath $sessionDir -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    ForEach-Object {
      $summary = Join-Path $_.FullName "summary.json"
      if (Test-Path -LiteralPath $summary) {
        try { $j = Get-Content -LiteralPath $summary -Raw | ConvertFrom-Json } catch { $j = $null }
        # Only the user's primary session: skip subagent and headless sessions.
        if ($j -and ($j.session_kind -in @("subagent", "headless"))) { return }
      }
      if (Test-Path -LiteralPath (Join-Path $_.FullName "signals.json")) { $_ }
    } |
    Select-Object -First 1
}

function Get-LastAssistant([string]$Dir) {
  $f = Join-Path $Dir "chat_history.jsonl"
  if (-not (Test-Path -LiteralPath $f)) { return "" }
  $last = ""
  foreach ($line in [IO.File]::ReadLines($f)) {
    if (-not $line.Trim()) { continue }
    try { $o = $line | ConvertFrom-Json } catch { continue }
    if ($o.type -eq "assistant" -and $o.content -is [string] -and $o.content.Trim()) { $last = $o.content.Trim() }
  }
  return $last
}

function Get-Prompts([string]$Dir, [string]$SessionId) {
  $f = Join-Path (Split-Path $Dir -Parent) "prompt_history.jsonl"
  if (-not (Test-Path -LiteralPath $f)) { return @() }
  $out = @()
  foreach ($line in [IO.File]::ReadLines($f)) {
    if (-not $line.Trim()) { continue }
    try { $o = $line | ConvertFrom-Json } catch { continue }
    if ($o.session_id -eq $SessionId -and $o.prompt) { $out += [string]$o.prompt }
  }
  if ($out.Count -gt 3) { $out = $out[($out.Count - 3)..($out.Count - 1)] }
  return $out
}

function Show-Toast([string]$Title, [string]$Message) {
  try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
    $nodes = $template.GetElementsByTagName("text")
    $nodes.Item(0).AppendChild($template.CreateTextNode($Title)) | Out-Null
    $nodes.Item(1).AppendChild($template.CreateTextNode($Message)) | Out-Null
    $toast = [Windows.UI.Notifications.ToastNotification]::new($template)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Grok Harness").Show($toast)
  } catch {
    Write-Log "toast fallback: $Title - $Message"
  }
}

$seen = @{}
$notified = @{}
$lastSid = $null
Write-Log "watching $Cwd (threshold $Threshold%)"

while ((Get-Date) -lt $deadline) {
  $session = Get-NewestSession
  if ($session) {
    $sid = $session.Name
    if ($sid -ne $lastSid) {
      $lastSid = $sid
      Write-Log "session $sid"
      # After /new, remind the fresh session to load the handoff.
      if (-not $notified.ContainsKey($sid) -and (Test-Path -LiteralPath $lastHandoffMarker)) {
        try { $h = Get-Content -LiteralPath $lastHandoffMarker -Raw | ConvertFrom-Json } catch { $h = $null }
        if ($h -and $h.path -and (Test-Path -LiteralPath $h.path) -and $h.session -ne $sid -and ([datetime]$h.created -gt (Get-Date).AddHours(-1))) {
          $leaf = Split-Path $h.path -Leaf
          Show-Toast "New Grok session" "Load the handoff: /pull-handoff $leaf"
          Write-Log "new-session notice $sid -> $($h.path)"
          $notified[$sid] = $true
        }
      }
    }

    try { $sig = Get-Content -LiteralPath (Join-Path $session.FullName "signals.json") -Raw | ConvertFrom-Json } catch { $sig = $null }
    if ($sig) {
      $pct = [int]$sig.contextWindowUsage
      $doneMarker = Join-Path $stateDir "$sid.done"
      if ($pct -ge $Threshold -and -not $seen.ContainsKey($sid) -and -not (Test-Path -LiteralPath $doneMarker)) {
        $summary = $null
        try { $summary = Get-Content -LiteralPath (Join-Path $session.FullName "summary.json") -Raw | ConvertFrom-Json } catch {}
        $goal = ""
        if ($summary) {
          if ($summary.session_summary -is [string]) { $goal = $summary.session_summary }
          elseif ($summary.last_recap -is [string]) { $goal = $summary.last_recap }
        }
        $prompts = Get-Prompts -Dir $session.FullName -SessionId $sid
        if (-not $goal -and $prompts.Count -gt 0) { $goal = [string]$prompts[0] }
        $last = Get-LastAssistant -Dir $session.FullName
        if ($last.Length -gt 2200) { $last = $last.Substring(0, 2200) + "`n… (truncated)" }
        $goalText = ($goal -replace "\s+", " ").Trim()
        if ($goalText.Length -gt 700) { $goalText = $goalText.Substring(0, 700) + "…" }
        $model = if ($summary -and $summary.current_model_id) { $summary.current_model_id } else { $sig.primaryModelId }
        $gitStatus = ""; $gitStat = ""
        try {
          $gitStatus = (& git -C $Cwd status --short 2>$null | Out-String).Trim()
          $gitStat = (& git -C $Cwd diff --stat 2>$null | Out-String).Trim()
        } catch {}
        $promptLines = ($prompts | ForEach-Object { "- " + (($_ -replace "\s+", " ").Trim()) }) -join "`n"
        if (-not $promptLines) { $promptLines = "- (not available)" }
        $slug = (Split-Path $Cwd -Leaf) -replace '[^A-Za-z0-9._-]', '-'
        $stamp = Get-Date -Format "yyyyMMdd-HHmm"
        $file = Join-Path $HandoffsRoot "handoff-$slug-$stamp.md"
        $body = @"
# Handoff: $slug - context $pct%

- **Date:** $(Get-Date -Format "yyyy-MM-dd HH:mm")
- **CWD:** $Cwd
- **Session:** $sid
- **Model:** $model
- **Context:** $pct% ($($sig.contextTokensUsed) / $($sig.contextWindowTokens) tokens; compactions: $($sig.compactionCount))

## Goal

$goalText

## Recent prompts

$promptLines

## Done (last assistant message)

$last

## Open

- Continue from the last turn. The full transcript is available with:
  ``grok export $sid`` (run from the project cwd).
- Re-read ``SPEC.md`` / ``DESIGN.md`` / ``AGENTS.md`` before editing.

## Key paths (git status)

``````
$gitStatus
``````

## Commands / state (git diff --stat)

``````
$gitStat
``````

## Risks / constraints

- Context reached $pct%; do not compact further. Run ``/new``, then ``/pull-handoff <this file>``.
- A new process can use: ``start-grok.ps1 -ResumeHandoff``.
- Model: $model. Use the harness routing: Flash implements, Pro plans/reviews.

## Do not redo

- Work described as done in the last assistant message above.
"@
        [IO.File]::WriteAllText($file, $body, (New-Object System.Text.UTF8Encoding($false)))
        $marker = @{ path = $file; session = $sid; created = (Get-Date).ToString("o") } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($lastHandoffMarker, $marker, (New-Object System.Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($doneMarker, $sid, (New-Object System.Text.UTF8Encoding($false)))
        $seen[$sid] = $true
        $leaf = Split-Path $file -Leaf
        Show-Toast "Grok context ${pct}%" "Handoff written: $leaf. Run /new, then /pull-handoff $leaf"
        Write-Log "handoff $file"
        if ($Once) { break }
      }
    }
  }
  if ($Once) { break }
  Start-Sleep -Seconds $PollSeconds
}
