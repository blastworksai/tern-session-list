@echo off
powershell -NoProfile -File "%~dp0session-list.ps1" %*
if errorlevel 1 exit /b 1
exit /b 0
