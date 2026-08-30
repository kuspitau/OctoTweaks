@echo off
setlocal
cd /d "%~dp0\.."

where py >nul 2>nul
if not errorlevel 1 (
  py -3 tools\check.py
) else (
  python tools\check.py
)

if errorlevel 1 (
  echo Packaging aborted because validation failed.
  pause
  exit /b 1
)

where py >nul 2>nul
if not errorlevel 1 (
  py -3 tools\package.py
) else (
  python tools\package.py
)

set ERR=%ERRORLEVEL%
pause
exit /b %ERR%
