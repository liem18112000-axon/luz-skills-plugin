@echo off
setlocal enabledelayedexpansion

REM ─── Inputs ───────────────────────────────────────────────────
REM Required:
REM   TENANT_ID    1st positional or env (e.g. be01bf45-611a-4011-90a8-76227db1d190)
REM   CACHE_KEY    2nd positional or env (e.g. CustomerIdAndEmaiMap)
REM Optional with defaults:
REM   NAMESPACE          default 'dev'
REM   PORT               default 8080  (starting local port — auto-increments if busy)
REM   REMOTE_PORT        default 8080  (api-forwarder service port; never increments)
REM   MAX_PORT_ATTEMPTS  default 10    (max consecutive ports to try)
REM   HOST               default localhost
REM   TOKEN              unset → auto-acquired (needs ADMIN_TENANT_ID)
REM   ADMIN_TENANT_ID    required when TOKEN unset
REM   TOKEN_PREFIX       default 'Bearer '
REM   BASIC_AUTH         default 'YWRtaW46YWRtaW4='   (forwarded to token skill)

if not "%~1"=="" set "TENANT_ID=%~1"
if not "%~2"=="" set "CACHE_KEY=%~2"

if not defined TENANT_ID (
    1>&2 echo ERROR: TENANT_ID is required ^(1st arg or env var^).
    1>&2 echo        Example: get_cache.cmd be01bf45-611a-4011-90a8-76227db1d190 CustomerIdAndEmaiMap
    exit /b 1
)
if not defined CACHE_KEY (
    1>&2 echo ERROR: CACHE_KEY is required ^(2nd arg or env var^).
    1>&2 echo        Example: get_cache.cmd be01bf45-611a-4011-90a8-76227db1d190 CustomerIdAndEmaiMap
    exit /b 1
)

if not defined NAMESPACE          set "NAMESPACE=dev"
if not defined PORT               set "PORT=8080"
if not defined REMOTE_PORT        set "REMOTE_PORT=8080"
if not defined MAX_PORT_ATTEMPTS  set "MAX_PORT_ATTEMPTS=10"
if not defined HOST               set "HOST=localhost"
if not defined BASIC_AUTH         set "BASIC_AUTH=YWRtaW46YWRtaW4="
if not defined TOKEN_PREFIX       set "TOKEN_PREFIX=Bearer "

set "_START_PORT=%PORT%"
set /a _attempts=0

:try_port
REM Reuse existing listener if one is already up
powershell -NoProfile -Command "$c = New-Object Net.Sockets.TcpClient; try { $c.Connect('%HOST%', %PORT%); exit 0 } catch { exit 1 } finally { $c.Close() }" >nul 2>&1
if %errorlevel%==0 (
    1>&2 echo [luz-cache] %HOST%:%PORT% already reachable - reusing.
    goto :have_port
)

set "LOG=%TEMP%\luz-portforward-%NAMESPACE%-%PORT%.log"
type nul > "%LOG%"
1>&2 echo [luz-cache] launching port-forward local:%PORT% -^> svc:api-forwarder:%REMOTE_PORT% ^(ns=%NAMESPACE%^)...
start "luz-port-forward-%NAMESPACE%-%PORT%" /min cmd /c "kubectl port-forward --address 0.0.0.0 services/api-forwarder %PORT%:%REMOTE_PORT% -n %NAMESPACE% > "%LOG%" 2>&1"

set /a _w=0
:wait_loop
set /a _w+=1
powershell -NoProfile -Command "Start-Sleep -Seconds 1; $c = New-Object Net.Sockets.TcpClient; try { $c.Connect('%HOST%', %PORT%); exit 0 } catch { exit 1 } finally { $c.Close() }" >nul 2>&1
if %errorlevel%==0 (
    1>&2 echo [luz-cache] port-forward ready on local port %PORT% (after !_w!s)
    goto :have_port
)
if !_w! LSS 7 goto :wait_loop

REM Did kubectl bail because of a port conflict?
findstr /i /c:"address already in use" /c:"unable to listen" /c:"bind:" "%LOG%" >nul 2>&1
if %errorlevel%==0 (
    set /a _attempts+=1
    set /a PORT+=1
    if !_attempts! LSS %MAX_PORT_ATTEMPTS% (
        1>&2 echo [luz-cache]   port busy - trying !PORT!...
        goto :try_port
    )
    1>&2 echo [luz-cache] ERROR: tried %MAX_PORT_ATTEMPTS% ports starting at %_START_PORT% - none worked.
    exit /b 1
)

1>&2 echo [luz-cache] ERROR: port-forward on %PORT% failed - see %LOG%
type "%LOG%" 1>&2
exit /b 1

:have_port
REM ─── Acquire token if missing ────────────────────────────────
if not defined TOKEN (
    if not defined ADMIN_TENANT_ID (
        1>&2 echo [luz-cache] ERROR: TOKEN not set and ADMIN_TENANT_ID missing - cannot authenticate.
        1>&2 echo              Pass TOKEN=... or ADMIN_TENANT_ID=...
        exit /b 2
    )
    set "TOKEN_SCRIPT=%~dp0..\luz-skill-get-token\get_token.cmd"
    if not exist "!TOKEN_SCRIPT!" (
        1>&2 echo [luz-cache] ERROR: companion script not found at !TOKEN_SCRIPT!
        exit /b 2
    )
    1>&2 echo [luz-cache] Acquiring token via luz-skill-get-token...
    for /f "usebackq delims=" %%T in (`call "!TOKEN_SCRIPT!" "%ADMIN_TENANT_ID%"`) do set "TOKEN=%%T"
    if not defined TOKEN (
        1>&2 echo [luz-cache] ERROR: token acquisition failed.
        exit /b 2
    )
)

REM ─── GET cache entry ─────────────────────────────────────────
set "URL=http://%HOST%:%PORT%/luz_cache/api/%TENANT_ID%/%CACHE_KEY%"
1>&2 echo [luz-cache] GET %URL%

set "BODY_FILE=%TEMP%\luz-cache-%RANDOM%.body"
for /f "usebackq delims=" %%C in (`curl -sS -o "%BODY_FILE%" -w "%%{http_code}" --location "%URL%" --header "Authorization: %TOKEN_PREFIX%%TOKEN%"`) do set "HTTP_CODE=%%C"

1>&2 echo [luz-cache] HTTP %HTTP_CODE%

if "%HTTP_CODE%"=="404" (
    echo not found
    if exist "%BODY_FILE%" del "%BODY_FILE%"
    exit /b 0
)

REM Determine if body is empty / "null"
for /f "usebackq delims=" %%X in (`powershell -NoProfile -Command "$b = (Get-Content -Raw -LiteralPath '%BODY_FILE%' -ErrorAction SilentlyContinue); if ([string]::IsNullOrWhiteSpace($b) -or ($b.Trim() -eq 'null')) { 'EMPTY' } else { 'OK' }"`) do set "BODY_STATE=%%X"

if "%BODY_STATE%"=="EMPTY" (
    echo not found
    if exist "%BODY_FILE%" del "%BODY_FILE%"
    exit /b 0
)

REM Pretty-print if JSON, else dump verbatim.
powershell -NoProfile -Command "$raw = Get-Content -Raw -LiteralPath '%BODY_FILE%'; try { $obj = $raw | ConvertFrom-Json -ErrorAction Stop; $obj | ConvertTo-Json -Depth 32 } catch { Write-Output $raw }"

if exist "%BODY_FILE%" del "%BODY_FILE%"

if /i "%HTTP_CODE:~0,1%" NEQ "2" (
    1>&2 echo [luz-cache] WARN: non-2xx response ^(%HTTP_CODE%^).
)

endlocal & exit /b 0
