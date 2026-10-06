@echo off
REM Double-click / shortcut friendly wrapper for start-grok.ps1
setlocal
set "SCRIPT=%USERPROFILE%\.grok\start-grok.ps1"
where pwsh >nul 2>&1 && (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
  exit /b %ERRORLEVEL%
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
exit /b %ERRORLEVEL%
