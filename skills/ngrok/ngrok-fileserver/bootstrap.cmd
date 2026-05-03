@echo off
REM bootstrap.cmd - verify python + ngrok + (optional) markdown package on Windows.
setlocal EnableDelayedExpansion
set "MISSING="

set "PY="
where python >nul 2>nul && set "PY=python"
if not defined PY where py >nul 2>nul && set "PY=py"

if not defined PY (
    where winget >nul 2>nul
    if errorlevel 1 (
        set "MISSING=!MISSING!|python - install from https://www.python.org/"
    ) else (
        echo [bootstrap] python not found - installing via winget 1>&2
        winget install -e --id Python.Python.3.12 --silent --accept-source-agreements --accept-package-agreements >nul 2>nul
        where python >nul 2>nul && set "PY=python"
        if not defined PY set "MISSING=!MISSING!|python - winget install failed; install manually"
    )
)

where ngrok >nul 2>nul
if errorlevel 1 (
    where winget >nul 2>nul
    if errorlevel 1 (
        set "MISSING=!MISSING!|ngrok - install from https://ngrok.com/download"
    ) else (
        echo [bootstrap] ngrok not found - installing via winget 1>&2
        winget install -e --id Ngrok.Ngrok --silent --accept-source-agreements --accept-package-agreements >nul 2>nul
        where ngrok >nul 2>nul
        if errorlevel 1 set "MISSING=!MISSING!|ngrok - winget install failed; install manually"
    )
)

where ngrok >nul 2>nul
if not errorlevel 1 (
    ngrok config check >nul 2>nul
    if errorlevel 1 (
        set "MISSING=!MISSING!|ngrok authtoken - sign up at https://dashboard.ngrok.com/get-started/your-authtoken, then run: ngrok config add-authtoken ^<YOUR-TOKEN^>"
    )
)

if defined PY (
    "%PY%" -c "import markdown" >nul 2>nul
    if errorlevel 1 (
        echo [bootstrap] python 'markdown' package not found - installing via pip --user 1>&2
        "%PY%" -m pip install --user markdown >nul 2>nul
    )
)

if defined MISSING (
    echo [bootstrap] MISSING - manual action required: 1>&2
    for %%M in ("!MISSING:|=" "!") do (
        if not "%%~M"=="" echo   - %%~M 1>&2
    )
    exit /b 1
)

echo [bootstrap] ready 1>&2
exit /b 0
