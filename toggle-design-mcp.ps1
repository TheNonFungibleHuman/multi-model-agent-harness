#Requires -Version 5.1
<#
.SYNOPSIS
  Enable/disable design MCP servers (and related design skills) for token-lean Grok.

.DESCRIPTION
  Default lean profile keeps Paper + Open Design MCP off so new chats do not pay
  MCP blurb / connection overhead on every turn.

  Usage:
    powershell -NoProfile -File $env:USERPROFILE\.grok\toggle-design-mcp.ps1 status
    powershell -NoProfile -File $env:USERPROFILE\.grok\toggle-design-mcp.ps1 on
    powershell -NoProfile -File $env:USERPROFILE\.grok\toggle-design-mcp.ps1 off

  Slash aliases: /mcp-design-on  /mcp-design-off  /mcp-design-status

.NOTES
  Edits ~/.grok/config.toml only (not lean/full templates).
  MCP toggle applies mid-session via /mcps -> r (no restart). The skill-catalog
  trim applies at the next session start.
#>

param(
  [Parameter(Position = 0)]
  [ValidateSet("status", "on", "off", "")]
  [string]$Action = "status"
)

$ErrorActionPreference = "Stop"
$configPath = Join-Path $env:USERPROFILE ".grok\config.toml"
if (-not (Test-Path -LiteralPath $configPath)) {
  throw "Missing config: $configPath"
}

# MCP servers controlled by this toggle (gemini-docs stays off)
$McpServers = @("paper", "open-design")

# Skills that only matter for design work
$DesignSkills = @(
  "animate",
  "animation-vocabulary",
  "apple-design",
  "emil-design-eng",
  "find-animation-opportunities",
  "improve-animations",
  "review-animations",
  "paper-vision",
  "pick-ui-library",
  "prototype",
  "design",
  "quiet-interfaces"
)

function Get-ConfigText {
  return [System.IO.File]::ReadAllText($configPath)
}

function Set-ConfigText {
  param([string]$Text)
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($configPath, $Text, $utf8NoBom)
}

function Get-McpEnabled {
  param([string]$Text, [string]$Name)
  $escaped = [regex]::Escape($Name)
  $pattern = "(?ms)\[mcp_servers\.$escaped\](.*?)(?=\r?\n\[|\z)"
  $m = [regex]::Match($Text, $pattern)
  if (-not $m.Success) { return $null }
  $em = [regex]::Match($m.Groups[1].Value, '(?m)^\s*enabled\s*=\s*(true|false)\s*$')
  if (-not $em.Success) { return $null }
  return ($em.Groups[1].Value -eq "true")
}

function Set-McpEnabled {
  param([string]$Text, [string]$Name, [bool]$Enabled)
  $val = if ($Enabled) { "true" } else { "false" }
  $escaped = [regex]::Escape($Name)
  # Isolate the whole [mcp_servers.NAME] section (until next [top-level] header)
  $secPat = "(?ms)(\[mcp_servers\.$escaped\]\r?\n)(.*?)(?=\r?\n\[|\z)"
  $m = [regex]::Match($Text, $secPat)
  if (-not $m.Success) {
    Write-Warning "Section [mcp_servers.$Name] not found in config.toml - skipped"
    return $Text
  }
  $header = $m.Groups[1].Value
  $body = $m.Groups[2].Value
  # Drop any existing enabled lines in this section, then add exactly one
  $body = [regex]::Replace($body, '(?m)^\s*enabled\s*=\s*(true|false)\s*\r?\n?', '')
  $body = $body.TrimEnd() + "`r`nenabled = $val`r`n"
  $replacement = $header + $body
  return $Text.Substring(0, $m.Index) + $replacement + $Text.Substring($m.Index + $m.Length)
}

function Get-DisabledSkills {
  param([string]$Text)
  $m = [regex]::Match($Text, '(?ms)^\s*disabled\s*=\s*\[(.*?)\]')
  if (-not $m.Success) { return @() }
  $rx = New-Object System.Text.RegularExpressions.Regex '"([^"]+)"'
  $list = New-Object System.Collections.Generic.List[string]
  foreach ($match in $rx.Matches($m.Groups[1].Value)) {
    [void]$list.Add($match.Groups[1].Value)
  }
  return $list.ToArray()
}

function Set-DisabledSkills {
  param([string]$Text, [string[]]$Names)
  $unique = @($Names | Where-Object { $_ } | Sort-Object -Unique)
  $lines = foreach ($n in $unique) { '    "{0}",' -f $n }
  if ($lines.Count -gt 0) {
    $inner = "`r`n" + ($lines -join "`r`n") + "`r`n"
  } else {
    $inner = ""
  }
  $block = "disabled = [$inner]"
  if ($Text -match '(?ms)^\s*disabled\s*=\s*\[.*?\]') {
    return [regex]::Replace($Text, '(?ms)^\s*disabled\s*=\s*\[.*?\]', $block, 1)
  }
  if ($Text -match '(?m)^\[skills\]\s*$') {
    return [regex]::Replace($Text, '(?m)^\[skills\]\s*$', "[skills]`r`n$block", 1)
  }
  return $Text + "`r`n[skills]`r`n$block`r`n"
}

function Show-Status {
  param([string]$Text)
  Write-Host "Design MCP toggle - $configPath"
  Write-Host ""
  foreach ($name in $McpServers) {
    $en = Get-McpEnabled -Text $Text -Name $name
    if ($null -eq $en) { $label = "MISSING" }
    elseif ($en) { $label = "ON" }
    else { $label = "OFF" }
    Write-Host ("  {0,-12} {1}" -f $name, $label)
  }
  $g = Get-McpEnabled -Text $Text -Name "gemini-docs"
  if ($null -eq $g) { $gl = "MISSING" }
  elseif ($g) { $gl = "ON" }
  else { $gl = "OFF" }
  Write-Host ("  {0,-12} {1}  (not controlled by this toggle; keep OFF unless debugging)" -f "gemini-docs", $gl)

  $disabled = @(Get-DisabledSkills -Text $Text)
  $designOn = @()
  $designOff = @()
  foreach ($s in $DesignSkills) {
    if ($disabled -contains $s) { $designOff += $s } else { $designOn += $s }
  }
  Write-Host ""
  Write-Host ("Design-related skills in catalog: {0} active, {1} disabled" -f $designOn.Count, $designOff.Count)
  if ($designOn.Count -gt 0) {
    Write-Host ("  active: " + ($designOn -join ", "))
  }
  Write-Host ""
  $flags = @()
  foreach ($name in $McpServers) {
    $flags += ,(Get-McpEnabled -Text $Text -Name $name)
  }
  $onCount = @($flags | Where-Object { $_ -eq $true }).Count
  $offCount = @($flags | Where-Object { $_ -eq $false }).Count
  if ($onCount -eq $McpServers.Count) {
    Write-Host "Mode: DESIGN MCP ON"
  } elseif ($offCount -eq $McpServers.Count) {
    Write-Host "Mode: DESIGN MCP OFF (token-lean)"
  } else {
    Write-Host "Mode: MIXED - run on or off to align"
  }
  Write-Host ""
  Write-Host "Commands:  toggle-design-mcp.ps1 on | off | status"
  Write-Host "Slash:     /mcp-design-on   /mcp-design-off   /mcp-design-status"
  Write-Host ""
  Write-Host "Apply NOW (no restart): run  /mcps  then press  r  to reload MCP servers"
  Write-Host "  from config.toml - the design MCP toggle is live immediately."
  Write-Host "  The [skills] disabled trim (catalog) is read at session start."
  Write-Host "Optional full refresh: quit Grok and start a NEW session."
}

function Enable-DesignMode {
  param([string]$Text)
  foreach ($name in $McpServers) {
    $Text = Set-McpEnabled -Text $Text -Name $name -Enabled $true
  }
  if ($null -ne (Get-McpEnabled -Text $Text -Name "gemini-docs")) {
    $Text = Set-McpEnabled -Text $Text -Name "gemini-docs" -Enabled $false
  }
  $disabled = @(Get-DisabledSkills -Text $Text)
  $disabled = @($disabled | Where-Object { $DesignSkills -notcontains $_ })
  $Text = Set-DisabledSkills -Text $Text -Names $disabled
  return $Text
}

function Disable-DesignMode {
  param([string]$Text)
  foreach ($name in $McpServers) {
    $Text = Set-McpEnabled -Text $Text -Name $name -Enabled $false
  }
  if ($null -ne (Get-McpEnabled -Text $Text -Name "gemini-docs")) {
    $Text = Set-McpEnabled -Text $Text -Name "gemini-docs" -Enabled $false
  }
  $disabled = @(Get-DisabledSkills -Text $Text)
  foreach ($s in $DesignSkills) {
    if ($disabled -notcontains $s) { $disabled += $s }
  }
  $Text = Set-DisabledSkills -Text $Text -Names $disabled
  return $Text
}

$text = Get-ConfigText

if ($Action -eq "" -or $Action -eq "status") {
  Show-Status -Text $text
  exit 0
}

if ($Action -eq "on") {
  $text = Enable-DesignMode -Text $text
  Set-ConfigText -Text $text
  Write-Host "Design MCP: ON (paper + open-design). Design skills re-enabled in config."
  Write-Host "gemini-docs left OFF."
  Write-Host ""
  Show-Status -Text (Get-ConfigText)
  exit 0
}

if ($Action -eq "off") {
  $text = Disable-DesignMode -Text $text
  Set-ConfigText -Text $text
  Write-Host "Design MCP: OFF. Design-related skills disabled in config."
  Write-Host ""
  Show-Status -Text (Get-ConfigText)
  exit 0
}
