# Grok skill shelf: enable/disable packs without copying files.
# Enable creates directory junctions under ~/.grok/skills -> shelf packs.
# Grok reloads skills when files change on disk (slash menu within a few seconds).
# Usage:
#   powershell -NoProfile -File $env:USERPROFILE\grok-skill-shelf\shelf.ps1 status
#   powershell -NoProfile -File $env:USERPROFILE\grok-skill-shelf\shelf.ps1 enable core
#   powershell -NoProfile -File $env:USERPROFILE\grok-skill-shelf\shelf.ps1 enable design
#   powershell -NoProfile -File $env:USERPROFILE\grok-skill-shelf\shelf.ps1 enable matt
#   powershell -NoProfile -File $env:USERPROFILE\grok-skill-shelf\shelf.ps1 enable video
#   powershell -NoProfile -File $env:USERPROFILE\grok-skill-shelf\shelf.ps1 enable extras
#   powershell -NoProfile -File $env:USERPROFILE\grok-skill-shelf\shelf.ps1 enable firecrawl
#   powershell -NoProfile -File $env:USERPROFILE\grok-skill-shelf\shelf.ps1 disable all|design|matt|video|extras|firecrawl
#   powershell -NoProfile -File $env:USERPROFILE\grok-skill-shelf\shelf.ps1 enable all

param(
  [Parameter(Position = 0, Mandatory = $true)]
  [ValidateSet('status', 'enable', 'disable')]
  [string]$Action,

  [Parameter(Position = 1)]
  [ValidateSet('core', 'design', 'matt', 'matt-pocock', 'video', 'extras', 'firecrawl', 'all', '')]
  [string]$Pack = ''
)

$ErrorActionPreference = 'Stop'
$ShelfRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LinkRoot = Join-Path $env:USERPROFILE '.grok\skills'
$ConfigPath = Join-Path $env:USERPROFILE '.grok\config.toml'

$PackDirs = @{
  core      = Join-Path $ShelfRoot 'core'      # the always-wanted 16
  design    = Join-Path $ShelfRoot 'design'
  matt      = Join-Path $ShelfRoot 'matt-pocock'
  video     = Join-Path $ShelfRoot 'video'
  extras    = Join-Path $ShelfRoot 'extras'
  firecrawl = Join-Path $ShelfRoot 'firecrawl'   # config-driven pack (no skill folders)
}

# Junction-driven packs (their skills physically live in grok-skill-shelf/<pack>).
$JunctionPacks = @('core', 'design', 'matt', 'video', 'extras')

# `all` deliberately excludes `core`: `/shelf-off` shelves the optional packs and
# leaves the baseline in place. Use `enable core` / `disable core` explicitly.

# firecrawl skills are NOT in a Grok scan root, so they are shelved via the
# [skills] disabled list in config.toml (the only way to toggle them).
$FirecrawlNames = @(
  'firecrawl','firecrawl-agent','firecrawl-build','firecrawl-build-interact','firecrawl-build-onboarding',
  'firecrawl-build-scrape','firecrawl-build-search','firecrawl-company-directories','firecrawl-competitive-intel',
  'firecrawl-crawl','firecrawl-dashboard-reporting','firecrawl-deep-research','firecrawl-demo-walkthrough',
  'firecrawl-download','firecrawl-interact','firecrawl-knowledge-base','firecrawl-knowledge-ingest',
  'firecrawl-lead-gen','firecrawl-lead-research','firecrawl-map','firecrawl-market-research','firecrawl-monitor',
  'firecrawl-parse','firecrawl-qa','firecrawl-research-index','firecrawl-research-papers','firecrawl-scrape',
  'firecrawl-search','firecrawl-seo-audit','firecrawl-shop','firecrawl-website-design-clone','firecrawl-workflows'
)

function Resolve-PackKey {
  param([string]$Name)
  switch ($Name) {
    'core' { 'core' }
    'design' { 'design' }
    'matt' { 'matt' }
    'matt-pocock' { 'matt' }
    'video' { 'video' }
    'extras' { 'extras' }
    'firecrawl' { 'firecrawl' }
    'all' { 'all' }
    default { throw "Unknown pack: $Name (use core, design, matt, video, extras, firecrawl, or all)" }
  }
}

function Get-PackSkillDirs {
  param([string]$Key)
  $dir = $PackDirs[$Key]
  if (-not (Test-Path $dir)) { throw "Missing pack folder: $dir" }
  Get-ChildItem -LiteralPath $dir -Directory | Sort-Object Name
}

function Test-IsJunctionOrSymlink {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $false }
  $item = Get-Item -LiteralPath $Path -Force
  return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Enable-Pack {
  param([string]$Key)
  $count = 0
  foreach ($skillDir in (Get-PackSkillDirs $Key)) {
    $link = Join-Path $LinkRoot $skillDir.Name
    if (Test-Path $link) {
      if (Test-IsJunctionOrSymlink $link) {
        # Another pack may own this name (core and matt-pocock overlap on four
        # skills). Only replace a link that is broken, not one owned elsewhere.
        $cur = @((Get-Item -LiteralPath $link -Force).Target)[0]
        if ($cur -and (Test-Path -LiteralPath $cur) -and ($cur.TrimEnd('\') -ne $skillDir.FullName.TrimEnd('\'))) {
          Write-Warning "Skip $($skillDir.Name): already linked to $cur (another pack owns it)."
          continue
        }
        $null = cmd /c "rmdir `"$link`""
      } else {
        Write-Warning "Skip $($skillDir.Name): real folder already exists at $link (not a junction). Move it aside first."
        continue
      }
    }
    New-Item -ItemType Junction -Path $link -Target $skillDir.FullName | Out-Null
    $count++
  }
  Write-Host "Enabled pack '$Key': linked $count skill(s) into $LinkRoot"
}

function Disable-Pack {
  param([string]$Key)
  $count = 0
  foreach ($skillDir in (Get-PackSkillDirs $Key)) {
    $link = Join-Path $LinkRoot $skillDir.Name
    if (-not (Test-Path $link)) { continue }
    if (-not (Test-IsJunctionOrSymlink $link)) {
      Write-Warning "Skip $($skillDir.Name): $link is a real folder, not a shelf junction."
      continue
    }
    $cur = @((Get-Item -LiteralPath $link -Force).Target)[0]
    if ($cur -and (Test-Path -LiteralPath $cur) -and ($cur.TrimEnd('\') -ne $skillDir.FullName.TrimEnd('\'))) {
      Write-Warning "Skip $($skillDir.Name): $link points at $cur (another pack owns it)."
      continue
    }
    # PowerShell Remove-Item often NRE on directory junctions; cmd rmdir is reliable.
    $null = cmd /c "rmdir `"$link`""
    if (Test-Path $link) {
      Write-Warning "Failed to remove junction: $link"
      continue
    }
    $count++
  }
  Write-Host "Disabled pack '$Key': removed $count junction(s) from $LinkRoot"
}

# ---- firecrawl (config-driven) ----
function Test-FirecrawlEnabled {
  if (-not (Test-Path $ConfigPath)) { return $false }
  $text = Get-Content -LiteralPath $ConfigPath -Raw
  # Enabled = firecrawl entries are ABSENT from [skills] disabled.
  return (-not ($text -match '(?m)^\s*"firecrawl'))
}

function Enable-Firecrawl {
  if (-not (Test-Path $ConfigPath)) { throw "No config.toml at $ConfigPath" }
  $lines = @(Get-Content -LiteralPath $ConfigPath)
  $out = @($lines | Where-Object { $_ -notmatch '^\s*"firecrawl' })
  if ($out.Count -eq $lines.Count) {
    Write-Host "firecrawl already enabled (no firecrawl-* entries in [skills] disabled)."
    return
  }
  Copy-Item -LiteralPath $ConfigPath -Destination "$ConfigPath.shelfbak" -Force
  ($out -join "`n") | Set-Content -LiteralPath $ConfigPath -NoNewline -Encoding UTF8
  Write-Host "Enabled firecrawl: removed firecrawl-* from [skills] disabled. (backup: config.toml.shelfbak)"
}

function Disable-Firecrawl {
  if (-not (Test-Path $ConfigPath)) { throw "No config.toml at $ConfigPath" }
  $lines = @(Get-Content -LiteralPath $ConfigPath)
  # Already has firecrawl entries -> done.
  if ($lines | Where-Object { $_ -match '^\s*"firecrawl' }) {
    Write-Host "firecrawl already disabled (firecrawl-* present in [skills] disabled)."
    return
  }
  # Insert firecrawl entries right after the `disabled = [` opening line.
  $insertIdx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*disabled\s*=\s*\[\s*$') { $insertIdx = $i; break }
  }
  if ($insertIdx -lt 0) {
    Write-Warning "Could not find '[skills] disabled = [' in config.toml; add firecrawl-* entries manually."
    return
  }
  $blank = $lines[$insertIdx] -replace '\S.*', '    '
  $insert = @()
  for ($n = 0; $n -lt $FirecrawlNames.Count; $n++) {
    # Always emit a trailing comma so the following original entry stays a valid array element.
    $insert += "$blank`"$($FirecrawlNames[$n])`","
  }
  $new = @()
  $new += $lines[0..$insertIdx]
  $new += $insert
  if ($insertIdx + 1 -lt $lines.Count) { $new += $lines[($insertIdx + 1)..($lines.Count - 1)] }
  Copy-Item -LiteralPath $ConfigPath -Destination "$ConfigPath.shelfbak" -Force
  ($new -join "`n") | Set-Content -LiteralPath $ConfigPath -NoNewline -Encoding UTF8
  Write-Host "Disabled firecrawl: added firecrawl-* to [skills] disabled. (backup: config.toml.shelfbak)"
}

function Show-Status {
  Write-Host "Shelf root: $ShelfRoot"
  Write-Host "Link root:  $LinkRoot"
  Write-Host ""
  $PackLabels = @{
    core      = 'core'
    design    = 'design'
    matt      = 'matt-pocock'
    video     = 'video'
    extras    = 'extras'
    firecrawl = 'firecrawl'
  }
  foreach ($key in @('core', 'design', 'matt', 'video', 'extras')) {
    $skills = @(Get-PackSkillDirs $key)
    $on = 0
    foreach ($s in $skills) {
      $link = Join-Path $LinkRoot $s.Name
      if (-not (Test-Path $link)) { continue }
      if (-not (Test-IsJunctionOrSymlink $link)) { continue }
      # Count only links that actually point into this pack: core and matt-pocock
      # share four skill names, so a name match alone overstates a pack.
      $cur = @((Get-Item -LiteralPath $link -Force).Target)[0]
      if ($cur -and ($cur.TrimEnd('\') -eq $s.FullName.TrimEnd('\'))) { $on++ }
    }
    $state = if ($on -eq 0) { 'OFF' } elseif ($on -eq $skills.Count) { 'ON' } else { "PARTIAL ($on/$($skills.Count))" }
    Write-Host ("  {0,-12} {1,-14} ({2} skills on shelf)" -f $PackLabels[$key], $state, $skills.Count)
  }
  # firecrawl is config-driven
  $fcState = if (Test-FirecrawlEnabled) { 'ON' } else { 'OFF' }
  Write-Host ("  {0,-12} {1,-14} (config-shelved via [skills] disabled)" -f 'firecrawl', $fcState)
  Write-Host ""
  Write-Host "Enable:  shelf.ps1 enable core|design|matt|video|extras|firecrawl|all"
  Write-Host "Disable: shelf.ps1 disable core|design|matt|video|extras|firecrawl|all"
  Write-Host "('all' = the optional packs; core is toggled on its own)"
  Write-Host "After enable/disable: wait a few seconds, or type / to refresh slash skills."
  Write-Host "If the agent still ignores the pack, start a new session (fallback)."
}

if ($Action -eq 'status') {
  Show-Status
  exit 0
}

if ([string]::IsNullOrWhiteSpace($Pack)) {
  throw "Pack required for $Action (core, design, matt, video, extras, firecrawl, or all)"
}

$resolved = Resolve-PackKey $Pack
$keys = if ($resolved -eq 'all') { @('design', 'matt', 'video', 'extras', 'firecrawl') } else { @($resolved) }

foreach ($k in $keys) {
  if ($k -eq 'firecrawl') {
    if ($Action -eq 'enable') { Enable-Firecrawl } else { Disable-Firecrawl }
  } else {
    if ($Action -eq 'enable') { Enable-Pack $k } else { Disable-Pack $k }
  }
}

Show-Status
