# Register the Grok token-ledger + auto-tuner for automatic start.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File "$HOME\.grok\token-ledger\register-startup.ps1"
#
# Registers one scheduled task, "GrokLedgerWatchdog", that runs start.ps1 every
# 15 minutes via run-hidden.vbs. wscript has no console of its own, so the task
# never flashes a terminal window on the desktop.
#
# The legacy "GrokTokenLedger" at-logon task and the Startup-folder shortcut are
# removed if present: they were redundant with the watchdog, and the logon task
# flashed a console window once per boot. Removing them needs an elevated shell;
# without one this script warns and continues.
#
# Unregister with unregister-startup.ps1.

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$startScript = Join-Path $root "start.ps1"
$vbs = Join-Path $root "run-hidden.vbs"
$taskName = "GrokLedgerWatchdog"
$legacyTask = "GrokTokenLedger"
$legacyLnk = Join-Path ([Environment]::GetFolderPath("Startup")) "Grok Token Ledger.lnk"

foreach ($f in @($startScript, $vbs)) {
    if (-not (Test-Path $f)) {
        Write-Error "required file not found: $f"
        exit 1
    }
}

$wscript = Join-Path $env:SystemRoot "System32\wscript.exe"
if (-not (Test-Path $wscript)) {
    $wscript = (Get-Command wscript.exe -ErrorAction Stop).Source
}

# ---- retire the legacy flashing starters -------------------------------------
if (Get-ScheduledTask -TaskName $legacyTask -ErrorAction SilentlyContinue) {
    try {
        Unregister-ScheduledTask -TaskName $legacyTask -Confirm:$false
        Write-Host "Removed legacy task: $legacyTask"
    }
    catch {
        Write-Warning "Could not remove $legacyTask (needs an Administrator shell): $($_.Exception.Message)"
    }
}
if (Test-Path $legacyLnk) {
    Remove-Item -LiteralPath $legacyLnk -Force
    Write-Host "Removed startup shortcut: $legacyLnk"
}

# ---- the hidden watchdog -----------------------------------------------------
$action = New-ScheduledTaskAction -Execute $wscript -Argument ('//B "{0}"' -f $vbs) -WorkingDirectory $root
# Interval without RepetitionDuration = repeat indefinitely (Duration stays empty).
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 15)
$settings = New-ScheduledTaskSettingsSet `
    -Hidden `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -MultipleInstances IgnoreNew

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Set-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings | Out-Null
    Write-Host "Updated scheduled task: $taskName (every 15 min, hidden)"
}
else {
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Description "Grok Build token ledger + auto-tuner, every 15 min, no console window" `
        -Force | Out-Null
    Write-Host "Registered scheduled task: $taskName (every 15 min, hidden)"
}

Write-Host ""
Write-Host "Starting the daemons now..."
& $wscript //B $vbs
Start-Sleep -Seconds 6
$pids = @()
foreach ($pf in @("ledger.pid", "tuner.pid")) {
    $p = Join-Path $root $pf
    if (Test-Path $p) { $pids += (Get-Content $p -ErrorAction SilentlyContinue) }
}
Write-Host "Daemon pids: $($pids -join ', ')"
Write-Host "Done. Ledger writes to $root\usage.jsonl, report at $root\report.md"
Write-Host ""
Write-Host "To remove autostart later:"
Write-Host ('  powershell -File "{0}"' -f (Join-Path $root "unregister-startup.ps1"))
