@echo off
REM serve.cmd <FOLDER>
REM Starts python file server + ngrok tunnel. Foreground; Ctrl-C stops both.
setlocal EnableDelayedExpansion
set "SKILL_DIR=%~dp0"
set "SKILL_DIR=%SKILL_DIR:~0,-1%"
set "SERVER_PY=%SKILL_DIR%\_lib\server.py"
set "DIR=%~1"
if "%DIR%"=="" (
    echo usage: serve.cmd ^<FOLDER^> 1>&2
    exit /b 2
)
if not exist "%DIR%\" (
    echo not a directory: %DIR% 1>&2
    exit /b 2
)
for %%I in ("%DIR%") do set "DIR=%%~fI"

if not defined PORT set "PORT=8765"

set "PY="
where python >nul 2>nul && set "PY=python"
if not defined PY where py >nul 2>nul && set "PY=py"
if not defined PY (
    echo python not found - run bootstrap.cmd first 1>&2
    exit /b 1
)

echo [serve] folder : %DIR% 1>&2
echo [serve] port   : %PORT% 1>&2

start /b "" "%PY%" "%SERVER_PY%" "%DIR%"

REM brief wait so server binds before ngrok dials
ping -n 2 127.0.0.1 >nul

if "%LOCAL_ONLY%"=="1" (
    echo [serve] LOCAL_ONLY=1 - public tunnel skipped
    echo [serve] open http://localhost:%PORT%/ in your browser
    pause
    goto :cleanup
)

where ngrok >nul 2>nul
if errorlevel 1 (
    echo [serve] ngrok not found - run bootstrap.cmd, or set LOCAL_ONLY=1 1>&2
    goto :cleanup
)

echo [serve] PUBLIC URL is anyone-with-link readable - don't share sensitive data 1>&2

if defined NGROK_REGION (
    ngrok http %PORT% --log=stdout --region=%NGROK_REGION%
) else (
    ngrok http %PORT% --log=stdout
)

:cleanup
REM Best-effort kill of the python server we started
for /f "tokens=2" %%P in ('tasklist /fi "imagename eq python.exe" /fo csv ^| findstr /i "python"') do (
    REM Skip — naive match would kill all python; user should Ctrl-C the window instead.
)
endlocal
exit /b 0
