@echo off
setlocal enabledelayedexpansion

REM ─── Inputs ───────────────────────────────────────────────────
REM Required:  ADMIN_TENANT_ID (env var) or 1st positional arg
REM Optional with defaults (override via env):
REM   NAMESPACE           default 'dev'
REM   PORT                default 8080  (starting local port — auto-increments if busy)
REM   REMOTE_PORT         default 8080  (api-forwarder service port; never increments)
REM   MAX_PORT_ATTEMPTS   default 10    (max consecutive ports to try)
REM   HOST                default localhost
REM   BASIC_AUTH          default 'YWRtaW46YWRtaW4='   (admin:admin)
REM
REM stdout: token value (only) on success.

if not "%~1"=="" set "ADMIN_TENANT_ID=%~1"

if not defined ADMIN_TENANT_ID (
    1>&2 echo ERROR: ADMIN_TENANT_ID is required ^(1st arg or env var^).
    1>&2 echo        Example: get_token.cmd 00a04daf-f2b3-41d5-8c12-2d1b4c48a36a
    exit /b 1
)

if not defined NAMESPACE          set "NAMESPACE=dev"
if not defined PORT               set "PORT=8080"
if not defined REMOTE_PORT        set "REMOTE_PORT=8080"
if not defined MAX_PORT_ATTEMPTS  set "MAX_PORT_ATTEMPTS=10"
if not defined HOST               set "HOST=localhost"
if not defined BASIC_AUTH         set "BASIC_AUTH=YWRtaW46YWRtaW4="

set "_START_PORT=%PORT%"
set /a _attempts=0

:try_port
REM Reuse if a listener is already up
powershell -NoProfile -Command "$c = New-Object Net.Sockets.TcpClient; try { $c.Connect('%HOST%', %PORT%); exit 0 } catch { exit 1 } finally { $c.Close() }" >nul 2>&1
if %errorlevel%==0 (
    1>&2 echo [luz-token] %HOST%:%PORT% already reachable - reusing.
    goto :do_request
)

set "LOG=%TEMP%\luz-portforward-%NAMESPACE%-%PORT%.log"
type nul > "%LOG%"
1>&2 echo [luz-token] launching port-forward local:%PORT% -^> svc:api-forwarder:%REMOTE_PORT% ^(ns=%NAMESPACE%^)...
start "luz-port-forward-%NAMESPACE%-%PORT%" /min cmd /c "kubectl port-forward --address 0.0.0.0 services/api-forwarder %PORT%:%REMOTE_PORT% -n %NAMESPACE% > "%LOG%" 2>&1"

set /a _w=0
:wait_loop
set /a _w+=1
powershell -NoProfile -Command "Start-Sleep -Seconds 1; $c = New-Object Net.Sockets.TcpClient; try { $c.Connect('%HOST%', %PORT%); exit 0 } catch { exit 1 } finally { $c.Close() }" >nul 2>&1
if %errorlevel%==0 (
    1>&2 echo [luz-token] port-forward ready on local port %PORT% (after !_w!s)
    goto :do_request
)
if !_w! LSS 7 goto :wait_loop

REM Did kubectl bail because of a port conflict?
findstr /i /c:"address already in use" /c:"unable to listen" /c:"bind:" "%LOG%" >nul 2>&1
if %errorlevel%==0 (
    set /a _attempts+=1
    set /a PORT+=1
    if !_attempts! LSS %MAX_PORT_ATTEMPTS% (
        1>&2 echo [luz-token]   port busy - trying !PORT!...
        goto :try_port
    )
    1>&2 echo [luz-token] ERROR: tried %MAX_PORT_ATTEMPTS% ports starting at %_START_PORT% - none worked.
    exit /b 1
)

1>&2 echo [luz-token] ERROR: port-forward on %PORT% failed - see %LOG%
type "%LOG%" 1>&2
exit /b 1

:do_request
set "URL=http://%HOST%:%PORT%/luzsec/api/%ADMIN_TENANT_ID%/access/tokens?type=all-tenant"
1>&2 echo [luz-token] POST %URL%

set "TMPFILE=%TEMP%\luz-token-resp-%RANDOM%.json"
curl -sS --location --request POST "%URL%" --header "Authorization: Basic %BASIC_AUTH%" -o "%TMPFILE%"
if errorlevel 1 (
    1>&2 echo [luz-token] ERROR: curl failed.
    if exist "%TMPFILE%" del "%TMPFILE%"
    exit /b 1
)

for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "try { (Get-Content -Raw -LiteralPath '%TMPFILE%' ^| ConvertFrom-Json).token } catch { '' }"`) do set "TOKEN=%%T"

del "%TMPFILE%" >nul 2>&1

if not defined TOKEN (
    1>&2 echo [luz-token] ERROR: no "token" field in response.
    exit /b 1
)
if "%TOKEN%"=="" (
    1>&2 echo [luz-token] ERROR: empty "token" field in response.
    exit /b 1
)

echo %TOKEN%
endlocal & exit /b 0
