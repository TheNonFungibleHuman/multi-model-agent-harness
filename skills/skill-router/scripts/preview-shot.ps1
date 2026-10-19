#Requires -Version 5.1
<#
.SYNOPSIS
  Screenshot a local page at an exact viewport size.
.DESCRIPTION
  Uses device-metrics emulation through Chrome DevTools Protocol (cdp-shot.mjs)
  so 390px mobile screenshots are laid out at 390px, not at Chrome's minimum
  window width and then cropped. Falls back to the Chrome --screenshot CLI when
  Node is unavailable.
.EXAMPLE
  .\preview-shot.ps1 -Url http://localhost:3000 -Out design/home.png
  .\preview-shot.ps1 -Url .\mockup.html -Out design/mobile.png -Width 390 -Height 844
#>
param(
  [Parameter(Mandatory)][string]$Url,
  [string]$Out = "preview.png",
  [int]$Width = 1440,
  [int]$Height = 900
)

$ErrorActionPreference = "Stop"

$candidates = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
)
$browser = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $browser) { throw "No Chrome/Edge found. Install one or set a browser path." }

if ($Url -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
  $Url = ([Uri](Resolve-Path -LiteralPath $Url).Path).AbsoluteUri
}

$outFull = [IO.Path]::GetFullPath($Out)
$outDir = Split-Path -Parent $outFull
if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

# Preferred path: CDP device-metrics emulation (exact viewport, no min-width crop).
$helper = Join-Path $PSScriptRoot 'cdp-shot.mjs'
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node -and (Test-Path -LiteralPath $helper)) {
  & $node.Source $helper $Url $outFull $Width $Height
  if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $outFull)) {
    Write-Output $outFull
    exit 0
  }
  Write-Warning 'cdp-shot failed; falling back to the Chrome CLI.'
}

$profile = Join-Path $env:TEMP ("preview-shot-" + [Guid]::NewGuid().ToString("N"))

& $browser --headless=new --disable-gpu --hide-scrollbars --no-first-run --no-default-browser-check `
  "--user-data-dir=$profile" "--window-size=$Width,$Height" "--screenshot=$outFull" $Url | Out-Null
Start-Sleep -Milliseconds 300
Remove-Item -LiteralPath $profile -Recurse -Force -ErrorAction SilentlyContinue
if (-not (Test-Path -LiteralPath $outFull)) { throw "Screenshot not written: $outFull" }
Write-Output $outFull
