# Unregister the Grok token-ledger + auto-tuner autostart.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File "$HOME\.grok\token-ledger\unregister-startup.ps1"
#
# Removes the watchdog task, the legacy logon task, and the Startup shortcut,
# then stops the two daemons. Data files (usage.jsonl, report.md, changes.log)
# are kept.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

foreach ($taskName in @("GrokLedgerWatchdog", "GrokTokenLedger")) {
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        try {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-Host "Removed scheduled task: $taskName"
        }
        catch {
            Write-Warning "Could not remove $taskName (needs an Administrator shell): $($_.Exception.Message)"
        }
    }
}

$lnkPath = Join-Path ([Environment]::GetFolderPath("Startup")) "Grok Token Ledger.lnk"
if (Test-Path $lnkPath) {
    Remove-Item -LiteralPath $lnkPath -Force
    Write-Host "Removed startup shortcut: $lnkPath"
}

foreach ($pidFile in @("ledger.pid", "tuner.pid")) {
    $p = Join-Path $root $pidFile
    if (Test-Path $p) {
        $oldPid = Get-Content $p -ErrorAction SilentlyContinue
        if ($oldPid) {
            $alive = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
            if ($alive) {
                Stop-Process -Id $oldPid -Force
                Write-Host "Stopped pid $oldPid"
            }
        }
        Remove-Item $p -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Done. Ledger/tuner stopped and removed from startup."
Write-Host "Data (usage.jsonl, report.md, changes.log) is kept in $root"
