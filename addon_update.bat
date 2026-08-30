@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem OctoTweaks - Deploy repository addon into OctoWoW
rem
rem Usage:
rem   addon_update.bat
rem   addon_update.bat "D:\Games\OctoWow"
rem
rem Default OctoWoW path:
rem   C:\Games\OctoWow
rem ============================================================

set "REPO_ROOT=%~dp0"
set "SOURCE=%REPO_ROOT%OctoTweaks"
set "WOW_ROOT=C:\Games\OctoWow"

if not "%~1"=="" set "WOW_ROOT=%~1"

set "DEST=%WOW_ROOT%\Interface\AddOns\OctoTweaks"

 echo.
echo ============================================================
echo OctoTweaks addon update
echo ============================================================
echo [INFO] Repository : %REPO_ROOT%
echo [INFO] Source     : %SOURCE%
echo [INFO] WoW root   : %WOW_ROOT%
echo [INFO] Destination: %DEST%
echo.

rem ------------------------------------------------------------
rem Safety checks before modifying the installed addon.
rem ------------------------------------------------------------

if not exist "%SOURCE%\OctoTweaks.toc" (
    echo [FAIL] Source addon not found:
    echo        %SOURCE%\OctoTweaks.toc
    goto :fail
)

if not exist "%WOW_ROOT%\Interface\AddOns" (
    echo [FAIL] WoW AddOns directory not found:
    echo        %WOW_ROOT%\Interface\AddOns
    echo.
    echo You can pass another OctoWoW root as the first argument:
    echo   addon_update.bat "D:\Games\OctoWow"
    goto :fail
)

if /I "%SOURCE%"=="%DEST%" (
    echo [FAIL] Source and destination are identical.
    echo        This script is intended to deploy a repository copy.
    goto :fail
)

rem ------------------------------------------------------------
rem Validate repository first. Installed addon remains untouched
rem if validation fails.
rem ------------------------------------------------------------

echo [INFO] Running repository checks...
pushd "%REPO_ROOT%"

where py >nul 2>nul
if not errorlevel 1 (
    py -3 tools\check.py
    set "CHECK_EXIT=!ERRORLEVEL!"
) else (
    where python >nul 2>nul
    if errorlevel 1 (
        popd
        echo [FAIL] Python 3 was not found in PATH.
        goto :fail
    )
    python tools\check.py
    set "CHECK_EXIT=!ERRORLEVEL!"
)

popd

if not "!CHECK_EXIT!"=="0" (
    echo.
    echo [FAIL] Repository validation failed.
    echo        Installed addon was NOT modified.
    goto :fail
)

echo [PASS] Repository validation

rem ------------------------------------------------------------
rem Remove the complete previous deployment so deleted/renamed
rem repository files cannot survive in Interface\AddOns.
rem ------------------------------------------------------------

if exist "%DEST%" (
    echo [INFO] Removing previous installed copy...
    rmdir /S /Q "%DEST%"

    if exist "%DEST%" (
        echo [FAIL] Could not remove previous addon directory:
        echo        %DEST%
        goto :fail
    )
    echo [PASS] Previous installed copy removed
) else (
    echo [INFO] No previous installed copy found
)

rem ------------------------------------------------------------
rem Copy exact current repository addon.
rem Robocopy success exit codes are 0 through 7.
rem ------------------------------------------------------------

echo [INFO] Copying current repository addon...
robocopy "%SOURCE%" "%DEST%" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS
set "ROBOCOPY_EXIT=%ERRORLEVEL%"

if %ROBOCOPY_EXIT% GEQ 8 (
    echo [FAIL] Robocopy failed with exit code %ROBOCOPY_EXIT%.
    goto :fail
)

if not exist "%DEST%\OctoTweaks.toc" (
    echo [FAIL] Deployment verification failed: OctoTweaks.toc is missing.
    goto :fail
)

echo.
echo ============================================================
echo [PASS] OctoTweaks deployed successfully
echo ============================================================
echo [INFO] Run /reload or restart WoW before testing changed Lua/TOC files.
echo.
pause
exit /b 0

:fail
echo.
echo ============================================================
echo [FAIL] OctoTweaks deployment aborted
echo ============================================================
echo.
pause
exit /b 1
