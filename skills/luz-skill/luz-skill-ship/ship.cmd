@echo off
setlocal

REM Thin Windows wrapper around ship.sh.

if "%~1"=="" (
    echo ERROR: MESSAGE is required.
    echo   Usage: ship.cmd "[LUZ-152936] ^<what changed^>"
    exit /b 1
)

set "SCRIPT_DIR=%~dp0"
bash "%SCRIPT_DIR%ship.sh" %*
