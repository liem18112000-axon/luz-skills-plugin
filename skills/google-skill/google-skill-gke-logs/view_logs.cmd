@echo off
setlocal enabledelayedexpansion

REM ─── Inputs ───────────────────────────────────────────────────
REM Required:  CONTAINER (env var) or 1st positional arg
REM Optional with org defaults (override any via env):
REM   NAMESPACE        default dev
REM   CLUSTER_NAME     default klara-nonprod
REM   CLUSTER_PROJECT  default klara-nonprod
REM   LIMIT            default 2000
REM   FRESHNESS        default 30m
REM Filter add-ons (each appended to the query when set):
REM   POD              filter by pod name
REM   SEVERITY         keep severity >= this value (e.g. ERROR)
REM   SEARCH           substring match on textPayload

if not "%~1"=="" set CONTAINER=%~1

if not defined CONTAINER (
    echo ERROR: CONTAINER is required (pass as 1st arg or env var^).
    echo        Example: view_logs.cmd luz-docs
    exit /b 1
)

REM ─── Org defaults ─────────────────────────────────────────────
if not defined CLUSTER_PROJECT set CLUSTER_PROJECT=klara-nonprod
if not defined CLUSTER_NAME    set CLUSTER_NAME=klara-nonprod
if not defined NAMESPACE       set NAMESPACE=dev
if not defined LIMIT           set LIMIT=2000
if not defined FRESHNESS       set FRESHNESS=30m

REM ─── Build filter ─────────────────────────────────────────────
set "FILTER=resource.type=k8s_container AND resource.labels.cluster_name=!CLUSTER_NAME! AND resource.labels.namespace_name=!NAMESPACE! AND resource.labels.container_name=!CONTAINER!"

if defined POD       set "FILTER=!FILTER! AND resource.labels.pod_name=!POD!"
if defined SEVERITY  set "FILTER=!FILTER! AND severity>=!SEVERITY!"
if defined SEARCH    set "FILTER=!FILTER! AND textPayload:!SEARCH!"

echo Reading Cloud Logging entries:
echo   project   = !CLUSTER_PROJECT!
echo   cluster   = !CLUSTER_NAME!
echo   namespace = !NAMESPACE!
echo   container = !CONTAINER!
if defined POD       echo   pod       = !POD!
echo   freshness = !FRESHNESS!
echo   limit     = !LIMIT!
if defined SEVERITY  echo   severity  = ^>=!SEVERITY!
if defined SEARCH    echo   search    = !SEARCH!
echo.

gcloud logging read "!FILTER!" ^
  --project=!CLUSTER_PROJECT! ^
  --limit=!LIMIT! ^
  --freshness=!FRESHNESS! ^
  --order=desc
