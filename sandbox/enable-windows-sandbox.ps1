#Requires -Version 5.1
<#
.SYNOPSIS
  Enable Windows Sandbox (requires an elevated PowerShell and a reboot).

.DESCRIPTION
  Windows Sandbox is a disposable Hyper-V-backed desktop. It is the right place
  to run untrusted repositories when the Grok harness guard is not enough
  (the guard is a policy boundary, not a kernel sandbox).

  Requirements: Windows 10/11 Pro, Enterprise or Education; virtualization
  enabled in firmware. This machine is Windows 11 Pro.

  Run in an elevated PowerShell:
    powershell -NoProfile -ExecutionPolicy Bypass -File $env:USERPROFILE\.grok\sandbox\enable-windows-sandbox.ps1

  Then reboot. Verify with:
    Get-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Error 'This script must run in an elevated PowerShell (Run as administrator).'
  exit 1
}

$feature = 'Containers-DisposableClientVM'
$state = (Get-WindowsOptionalFeature -Online -FeatureName $feature).State
Write-Host "Current state: $feature = $state"

if ($state -eq 'Enabled') {
  Write-Host 'Windows Sandbox is already enabled.'
  exit 0
}

Write-Host 'Enabling Windows Sandbox...'
$result = Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart
if ($result.RestartNeeded) {
  Write-Host ''
  Write-Host 'Enabled. A reboot is required before WindowsSandbox.exe is usable.' -ForegroundColor Yellow
  Write-Host 'After rebooting, run:'
  Write-Host "  powershell -NoProfile -File `"$env:USERPROFILE\.grok\sandbox\run-in-sandbox.ps1`" -Repo <path>"
} else {
  Write-Host 'Enabled. No reboot reported as required.'
}
