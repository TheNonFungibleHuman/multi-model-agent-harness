#Requires -Version 5.1
<#
.SYNOPSIS
  Install the anti-slop pre-commit hook into a git repository.
.DESCRIPTION
  Writes .git/hooks/pre-commit to run the Impeccable detector on staged UI
  files. The commit is blocked (exit 2) while findings exist. Use this in any
  product repository where the Stop hook is not enough.
.EXAMPLE
  .\install-design-guard.ps1 -Repo C:\Users\User\my-product
#>
param([string]$Repo = ".")

$ErrorActionPreference = "Stop"
$repoFull = (Resolve-Path -LiteralPath $Repo).Path
$gitDir = Join-Path $repoFull ".git"
if (-not (Test-Path -LiteralPath $gitDir)) { throw "Not a git repository: $repoFull" }

$script = (Join-Path $env:USERPROFILE ".grok\skills\skill-router\scripts\anti-slop-stop.py") -replace "\\", "/"
$hook = "#!/bin/sh`npython `"$script`" --staged`n"

$hooksDir = Join-Path $gitDir "hooks"
New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null
$hookPath = Join-Path $hooksDir "pre-commit"
if (Test-Path -LiteralPath $hookPath) {
    Copy-Item $hookPath "$hookPath.bak-$(Get-Date -Format yyyyMMddHHmmss)" -Force
}
[IO.File]::WriteAllText($hookPath, $hook)
Write-Output "Installed $hookPath"
