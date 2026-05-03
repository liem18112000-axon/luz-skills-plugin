@echo off
setlocal enabledelayedexpansion

REM ─── Inputs ───────────────────────────────────────────────────
REM Required:  SERVICE (env var) or 1st positional arg
REM Optional with org defaults (override any via env):
REM   PROJECT     default klara-nonprod
REM   REGION      default europe-west6
REM   LIMIT       default 2000
REM   FRESHNESS   default 30m
REM Filter add-ons (each appended to the query when set):
REM   REVISION    filter by revision name
REM   SEVERITY    keep severity >= this value (e.g. ERROR)
REM   SEARCH      substring match on textPayload

if not "%~1"=="" set SERVICE=%~1

if not defined SERVICE (
    echo ERROR: SERVICE is required (pass as 1st arg or env var^).
    echo        Example: view_cloudrun_logs.cmd dev-luz-thumbnail
    exit /b 1
)

REM ─── Org defaults ─────────────────────────────────────────────
if not defined PROJECT     set PROJECT=klara-nonprod
if not defined REGION      set REGION=europe-west6
if not defined LIMIT       set LIMIT=2000
if not defined FRESHNESS   set FRESHNESS=30m

REM ─── Build filter ─────────────────────────────────────────────
set "FILTER=resource.type=cloud_run_revision AND resource.labels.service_name=!SERVICE! AND resource.labels.location=!REGION!"

if defined REVISION  set "FILTER=!FILTER! AND resource.labels.revision_name=!REVISION!"
if defined SEVERITY  set "FILTER=!FILTER! AND severity>=!SEVERITY!"
if defined SEARCH    set "FILTER=!FILTER! AND textPayload:!SEARCH!"

echo Reading Cloud Run logs:
echo   project   = !PROJECT!
echo   service   = !SERVICE!
echo   region    = !REGION!
if defined REVISION  echo   revision  = !REVISION!
echo   freshness = !FRESHNESS!
echo   limit     = !LIMIT!
if defined SEVERITY  echo   severity  = ^>=!SEVERITY!
if defined SEARCH    echo   search    = !SEARCH!
echo.

gcloud logging read "!FILTER!" ^
  --project=!PROJECT! ^
  --limit=!LIMIT! ^
  --freshness=!FRESHNESS! ^
  --order=desc
