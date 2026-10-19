#Requires -Version 5.1
<#
.SYNOPSIS
  Run a pen.dev design task in a child Grok session that has pencil MCP,
  while the calling session stays token-lean (no pencil tools).

.DESCRIPTION
  The child is a `start-grok.ps1 -Design -Inspo` session: pencil and Inspo are
  enabled for the child only, then restored when it exits. The child reads the
  pen-dev skill, studies user references or Inspo, designs on the canvas, and
  exports a PNG to the requested folder.

  The parent session never loads pencil or Inspo tools. This is the per-task
  "pick it up, use it, put it down" design lane.

.EXAMPLE
  powershell -NoProfile -File "$env:USERPROFILE\.grok\skills\skill-router\scripts\design-lane.ps1" `
    -Brief "A calm landing page for a two-person meal planner" `
    -Cwd C:\work\supper -Out C:\work\supper\design\directions\supper-pen `
    -References "https://example.com/ref1, C:\refs\screenshot.png, editorial but not cream"
#>
param(
  [Parameter(Mandatory = $true)][string]$Brief,
  [string]$Out = "",
  [string]$Cwd = (Get-Location).Path,
  [string]$References = "",
  [switch]$NoInspo,
  [int]$MaxTurns = 24,
  [switch]$KeepPrompt
)

$ErrorActionPreference = 'Stop'

$start = Join-Path $env:USERPROFILE '.grok\start-grok.ps1'
if (-not (Test-Path -LiteralPath $start)) { throw "start-grok.ps1 not found at $start" }
if (-not (Test-Path -LiteralPath $Cwd -PathType Container)) { throw "Cwd not found: $Cwd" }
$cwdFull = (Resolve-Path -LiteralPath $Cwd).Path

if (-not $Out) { $Out = Join-Path $cwdFull 'design\directions\design-lane' }
$outFull = [IO.Path]::GetFullPath($Out)
New-Item -ItemType Directory -Force -Path $outFull | Out-Null
$preview = Join-Path $outFull 'preview.png'

$refBlock = if ($References.Trim()) { $References.Trim() } else { "None provided." }
$inspoBlock = if ($NoInspo) {
  "Do not use the Inspo MCP. Work from the brief and the user's references only."
} else {
  "If no references were provided, use the Inspo MCP: call recommend (or the closest search tool) with the brief, pick 2-3 relevant references, and extract their principles. If references were provided, use Inspo only to supplement them."
}

$prompt = @"
You are the design lane for the Grok harness. Work only on the pen.dev canvas.

1. Read the pen-dev skill with the pencil read_skill tool before acting.
2. Call pencil get_app_state. Work in the active document. Create a new frame named "Design lane - <short name>" if needed; do not modify unrelated frames.
3. Design this brief: $Brief
4. Reference study.
   User references: $refBlock
   $inspoBlock
   Steal like an artist: synthesize 2-3 sources into a new direction. Extract the why (hierarchy, type scale, spacing, composition, tone), then make original choices. Never copy one layout 1:1, never reuse copy, logos, or brand assets, and never blindly copy a palette. If a reference conflicts with the banned tells below, the banned tells win.
5. Use the pencil execute tool and the pen-dev skill's rules. Favor real hierarchy, readable type, and one clear idea over decoration. Keep it complete, not a wireframe.
   Avoid the harness's banned tells: Inter/Roboto/Arial/Fraunces as display type, purple gradients, cream page backgrounds, emoji icons, left-bar callout cards, and multiple primary CTAs for one action.
   Do not invent testimonials, quotes, metrics, or customer names. If there is no real proof, omit the proof section.
6. Before exporting, review the frame against the canvas checklist: one idea, hierarchy, type contrast, one accent/CTA, 4.5:1 body contrast, spacing with no clipping or collisions, real copy, no banned tells, and originality (not a 1:1 copy of a reference). Fix issues in the canvas first.
7. In the final summary, list each checklist item as pass or fixed, the frame name, the export path, and which references you synthesized.
8. Export the finished frame as a PNG into this exact folder: $outFull
   The exporter may write <nodeId>.png; after exporting, copy/rename that file to:
   $preview
9. Do not edit application source code, config.toml, or harness files.
10. End with the summary from step 7.

The parent session is waiting and has no pencil tools. If a tool is unavailable, say so and stop; do not invent files.
"@

$promptFile = Join-Path $env:TEMP ("grok-design-lane-" + [guid]::NewGuid().ToString('N') + ".md")
[System.IO.File]::WriteAllText($promptFile, $prompt, (New-Object System.Text.UTF8Encoding $false))

Push-Location -LiteralPath $cwdFull
try {
  $childArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $start, '-Design')
  if (-not $NoInspo) { $childArgs += '-Inspo' }
  $childArgs += @('--prompt-file', $promptFile, '--always-approve', '--max-turns', $MaxTurns)
  & powershell @childArgs
  $code = $LASTEXITCODE
} finally {
  Pop-Location
}

if (Test-Path -LiteralPath $preview) {
  $size = (Get-Item -LiteralPath $preview).Length
  Write-Output "design-lane: preview $preview ($size bytes)"
} else {
  Write-Warning "design-lane: child finished but no preview.png at $preview"
  $code = if ($code) { $code } else { 2 }
}

if (-not $KeepPrompt) {
  Remove-Item -LiteralPath $promptFile -Force -ErrorAction SilentlyContinue
}
exit $code
