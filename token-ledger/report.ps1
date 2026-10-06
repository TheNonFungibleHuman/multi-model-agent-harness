# Regenerate the Grok token ledger report on demand.
# Usage: powershell -ExecutionPolicy Bypass -File "$HOME\.grok\token-ledger\report.ps1"
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { $python = (Get-Command py -ErrorAction SilentlyContinue).Source }
if (-not $python) { Write-Error "python not found on PATH"; exit 1 }
& $python -u (Join-Path $root "ledger.py") --report
