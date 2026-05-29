@echo off
echo Stopping TorrServer...
taskkill /IM TorrServer-windows-amd64.exe /F >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  echo TorrServer stopped.
) else (
  echo TorrServer was not running or could not be stopped.
)
pause
