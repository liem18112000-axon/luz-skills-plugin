@echo off
setlocal

REM Thin Windows wrapper around check_materialize.sh.
REM Most callers should run the .sh from Git Bash / WSL.

if "%~1"=="" (
    echo ERROR: TENANT_ID is required.
    echo   Usage: check_materialize.cmd ^<TENANT_ID^>
    exit /b 1
)

set "SCRIPT_DIR=%~dp0"
bash "%SCRIPT_DIR%check_materialize.sh" %*
