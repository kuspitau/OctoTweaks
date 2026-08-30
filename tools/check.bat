@echo off
setlocal
cd /d "%~dp0\.."

where py >nul 2>nul
if not errorlevel 1 (
  py -3 tools\check.py
) else (
  python tools\check.py
)

set ERR=%ERRORLEVEL%
pause
exit /b %ERR%
