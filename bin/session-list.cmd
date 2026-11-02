@echo off
rem session-list: Windows shim for session-list.ps1. Prefers PowerShell 7 (pwsh),
rem falls back to Windows PowerShell; passes every argument and stdin; returns
rem the script's exit code (0 ok, 1 error, 2 check --hook reminder).
rem if-else on purpose: chaining on success or failure would rerun the command when pwsh exits non-zero.
where pwsh >nul 2>nul
if errorlevel 1 (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0session-list.ps1" %*
) else (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0session-list.ps1" %*
)
exit /b %errorlevel%
