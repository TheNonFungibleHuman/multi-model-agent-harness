#Requires -Version 5.1
<#
.SYNOPSIS
  Launch a repository in Windows Sandbox as a disposable, network-isolated copy.

.DESCRIPTION
  The host repo is mapped read-only into the sandbox. A small boot script copies
  it to C:\work inside the guest and opens a PowerShell prompt there. Writes in
  the guest never reach the host repo.

  Requires Windows Sandbox to be enabled (see enable-windows-sandbox.ps1).
  Windows Sandbox is Windows Pro/Enterprise/Education only.

  Usage:
    powershell -NoProfile -File $env:USERPROFILE\.grok\sandbox\run-in-sandbox.ps1 -Repo C:\path\to\repo
    powershell -NoProfile -File $env:USERPROFILE\.grok\sandbox\run-in-sandbox.ps1 -Repo . -AllowNetwork
    powershell -NoProfile -File $env:USERPROFILE\.grok\sandbox\run-in-sandbox.ps1 -Repo . -ReadWrite

  -ReadWrite maps the host repo directly (changes persist). Prefer the default:
  a disposable copy.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Repo,
  [switch]$AllowNetwork,
  [switch]$ReadWrite,
  [switch]$KeepConfig,
  [switch]$GenerateOnly
)

$ErrorActionPreference = 'Stop'

$sandboxExe = Join-Path $env:WINDIR 'System32\WindowsSandbox.exe'
if (-not (Test-Path -LiteralPath $sandboxExe) -and -not $GenerateOnly) {
  Write-Error @'
Windows Sandbox is not available on this machine.
Run the elevated setup first, then reboot:
  powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.grok\sandbox\enable-windows-sandbox.ps1"
'@
  exit 1
}

if (-not (Test-Path -LiteralPath $Repo -PathType Container)) {
  Write-Error "Repo not found: $Repo"
  exit 1
}
$repoFull = (Resolve-Path -LiteralPath $Repo).Path

# Temp workspace for the guest boot script and the generated .wsb.
$stage = Join-Path $env:TEMP ('grok-sandbox-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$entryHost = Join-Path $stage 'entry'
New-Item -ItemType Directory -Path $entryHost -Force | Out-Null

$copyBlock = if ($ReadWrite) {
  'New-Item -ItemType Junction -Path C:\work -Target C:\repo -Force | Out-Null'
} else {
  'robocopy C:\repo C:\work /E /NFL /NDL /NJH /NJS /NP | Out-Null'
}

$entry = @"
`$ErrorActionPreference = 'Continue'
$copyBlock
Set-Location C:\work
Write-Host ''
Write-Host 'Grok sandbox: disposable copy at C:\work' -ForegroundColor Cyan
Write-Host 'The host repo is mapped read-only at C:\repo.' -ForegroundColor DarkGray
Write-Host 'Run the agent here only; do not paste host secrets into the guest.' -ForegroundColor DarkGray
Write-Host ''
`$env:GROK_SANDBOX = '1'
Start-Process powershell -ArgumentList '-NoExit','-NoProfile','-ExecutionPolicy','Bypass' -WorkingDirectory C:\work
"@
[System.IO.File]::WriteAllText((Join-Path $entryHost 'start.ps1'), $entry, (New-Object System.Text.UTF8Encoding $false))

$network = if ($AllowNetwork) { 'Enable' } else { 'Disable' }
$readOnly = if ($ReadWrite) { 'false' } else { 'true' }

$wsb = @"
<Configuration>
  <VGpu>Disable</VGpu>
  <Networking>$network</Networking>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$repoFull</HostFolder>
      <SandboxFolder>C:\repo</SandboxFolder>
      <ReadOnly>$readOnly</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$entryHost</HostFolder>
      <SandboxFolder>C:\entry</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\entry\start.ps1</Command>
  </LogonCommand>
</Configuration>
"@

$wsbPath = Join-Path $stage 'repo.wsb'
[System.IO.File]::WriteAllText($wsbPath, $wsb, (New-Object System.Text.UTF8Encoding $false))

Write-Host "Repo:     $repoFull"
Write-Host "Mode:     $(if ($ReadWrite) { 'read-write mapping' } else { 'disposable copy' })"
Write-Host "Network:  $network"
Write-Host "Config:   $wsbPath"
Write-Host ''
if ($GenerateOnly) {
  Write-Host 'Generated only; not launching Windows Sandbox.'
  exit 0
}
Write-Host 'Starting Windows Sandbox...'
& $sandboxExe $wsbPath

if (-not $KeepConfig) {
  # The guest reads the config at launch; leave it on disk for this session so a
  # retry works, and let the OS clean %TEMP% later. Printing the path is enough.
  Write-Host "Sandbox config kept at: $wsbPath"
}
