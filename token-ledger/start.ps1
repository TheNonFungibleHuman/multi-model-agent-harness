# Start Grok token-ledger + auto-tuner (Grok Build helpers)
# Usage: powershell -ExecutionPolicy Bypass -File "$HOME\.grok\token-ledger\start.ps1"
# Compatible with Windows PowerShell 5.1+
#
# Idempotent: safe to run every 15 min from the GrokLedgerWatchdog scheduled task.
# Appends one line per run to start.log, so a watchdog run can be audited.
#
# Launches two detached python processes:
#   ledger.py   - tails ~/.grok/logs/unified.jsonl -> usage.jsonl + report.md
#   tuner.py    - auto-tunes config.toml every 15 min (bounded, logged)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ledgerPidFile = Join-Path $root "ledger.pid"
$tunerPidFile = Join-Path $root "tuner.pid"
$logFile = Join-Path $root "start.log"

function Write-Log([string]$msg) {
    "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz') | $msg" |
        Add-Content -Path $logFile -Encoding utf8 -ErrorAction SilentlyContinue
}

function Test-Alive($pidFile) {
    if (-not (Test-Path $pidFile)) { return $false }
    $oldPid = Get-Content $pidFile -ErrorAction SilentlyContinue
    if (-not $oldPid) { return $false }
    return $null -ne (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)
}

if ((Test-Alive $ledgerPidFile) -and (Test-Alive $tunerPidFile)) {
    Write-Log "no-op: ledger + tuner already alive"
    Write-Host "token-ledger + auto-tuner already running"
    exit 0
}

$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) { $pythonCmd = Get-Command py -ErrorAction SilentlyContinue }
if (-not $pythonCmd) {
    Write-Log "FAIL: python not found on PATH (PATH=$env:PATH)"
    Write-Error "python not found on PATH"
    exit 1
}
$python = $pythonCmd.Source

# Detached processes. stdout/stderr are redirected so that a crash leaves a
# traceback behind; without that, a dead daemon is invisible (which is exactly
# how this pair stayed dead for eight days in September 2026).
if (-not (Test-Alive $ledgerPidFile)) {
    Write-Host "Starting token-ledger ..."
    $proc = Start-Process -FilePath $python `
        -ArgumentList @("-u", (Join-Path $root "ledger.py")) `
        -WorkingDirectory $root -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $root "ledger.out.log") `
        -RedirectStandardError (Join-Path $root "ledger.err.log")
    $proc.Id | Set-Content -Path $ledgerPidFile -Encoding ascii
    Start-Sleep -Milliseconds 800
    if ($proc.HasExited) {
        Remove-Item $ledgerPidFile -ErrorAction SilentlyContinue
        Write-Log "FAIL: ledger exited immediately (code $($proc.ExitCode)) via $python"
        Write-Error "token-ledger exited immediately (code $($proc.ExitCode)). Run: python -u `"$(Join-Path $root 'ledger.py')`""
        exit 1
    }
    Write-Log "started ledger pid $($proc.Id) via $python"
    Write-Host "OK: token-ledger up (pid $($proc.Id))"
}

if (-not (Test-Alive $tunerPidFile)) {
    Write-Host "Starting auto-tuner ..."
    $proc = Start-Process -FilePath $python `
        -ArgumentList @("-u", (Join-Path $root "tuner.py"), "--loop") `
        -WorkingDirectory $root -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $root "tuner.out.log") `
        -RedirectStandardError (Join-Path $root "tuner.err.log")
    $proc.Id | Set-Content -Path $tunerPidFile -Encoding ascii
    Start-Sleep -Milliseconds 800
    if ($proc.HasExited) {
        Remove-Item $tunerPidFile -ErrorAction SilentlyContinue
        Write-Log "FAIL: tuner exited immediately (code $($proc.ExitCode)) via $python"
        Write-Error "auto-tuner exited immediately (code $($proc.ExitCode)). Run: python -u `"$(Join-Path $root 'tuner.py')`" --loop"
        exit 1
    }
    Write-Log "started tuner pid $($proc.Id) via $python"
    Write-Host "OK: auto-tuner up (pid $($proc.Id))"
}

Write-Log "done"
Write-Host "Done. Report: $root\report.md  (refreshes every 15 min)"
