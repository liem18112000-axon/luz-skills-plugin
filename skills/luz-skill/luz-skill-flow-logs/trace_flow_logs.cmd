@echo off
setlocal enabledelayedexpansion

REM Read interleaved Cloud Logging entries across the Luz request flow:
REM   luz-webclient -> luz-docs-view-controller -> luz-docs -> luz-jsonstore
REM
REM Multi-service counterpart of google-skill-gke-logs (single container).
REM
REM Required (highly recommended): SEARCH (env var or 1st positional arg)
REM   Substring on textPayload, usually a tenant id or request id.
REM
REM Optional with org defaults (override any via env):
REM   NAMESPACE        default dev
REM   CLUSTER_NAME     default klara-nonprod
REM   CLUSTER_PROJECT  default klara-nonprod
REM   LIMIT            default 5000
REM   FRESHNESS        default 30m
REM   SEVERITY         keep severity >= this value
REM   SERVICES         comma-list, default
REM                    luz-webclient,luz-docs-view-controller,luz-docs,luz-jsonstore

if not "%~1"=="" set SEARCH=%~1

REM ─── Org defaults ─────────────────────────────────────────────
if not defined CLUSTER_PROJECT set CLUSTER_PROJECT=klara-nonprod
if not defined CLUSTER_NAME    set CLUSTER_NAME=klara-nonprod
if not defined NAMESPACE       set NAMESPACE=dev
if not defined LIMIT           set LIMIT=5000
if not defined FRESHNESS       set FRESHNESS=30m
if not defined SERVICES        set SERVICES=luz-webclient,luz-docs-view-controller,luz-docs,luz-jsonstore

REM ─── Build container OR clause ────────────────────────────────
set "CONTAINER_CLAUSE="
for %%S in (%SERVICES:,= %) do (
    if defined CONTAINER_CLAUSE (
        set "CONTAINER_CLAUSE=!CONTAINER_CLAUSE! OR resource.labels.container_name=%%S"
    ) else (
        set "CONTAINER_CLAUSE=resource.labels.container_name=%%S"
    )
)

REM ─── Build full filter ────────────────────────────────────────
set "FILTER=resource.type=k8s_container AND resource.labels.cluster_name=!CLUSTER_NAME! AND resource.labels.namespace_name=!NAMESPACE! AND (!CONTAINER_CLAUSE!)"

if defined SEVERITY  set "FILTER=!FILTER! AND severity>=!SEVERITY!"
if defined SEARCH    set "FILTER=!FILTER! AND textPayload:!SEARCH!"

echo Reading Cloud Logging entries across Luz flow:
echo   project   = !CLUSTER_PROJECT!
echo   cluster   = !CLUSTER_NAME!
echo   namespace = !NAMESPACE!
echo   services  = !SERVICES!
echo   freshness = !FRESHNESS!
echo   limit     = !LIMIT!
if defined SEVERITY  echo   severity  = ^>=!SEVERITY!
if defined SEARCH    echo   search    = !SEARCH!
echo.

gcloud logging read "!FILTER!" --project=!CLUSTER_PROJECT! --limit=!LIMIT! --freshness=!FRESHNESS! --order=desc
