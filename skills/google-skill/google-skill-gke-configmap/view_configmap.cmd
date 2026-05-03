@echo off
setlocal enabledelayedexpansion

REM ─── Inputs ───────────────────────────────────────────────────
REM Required:  CONFIGMAP (env var) or 1st positional arg
REM Optional:
REM   NAMESPACE   default dev
REM   OUTPUT      default yaml (alternatives: json, data)

if not "%~1"=="" set CONFIGMAP=%~1

if not defined CONFIGMAP (
    echo ERROR: CONFIGMAP is required (pass as 1st arg or env var^).
    echo        Example: view_configmap.cmd luz-docs-env-configmap-h7h69gmbt2
    exit /b 1
)

if not defined NAMESPACE set NAMESPACE=dev
if not defined OUTPUT    set OUTPUT=yaml

echo ConfigMap: !CONFIGMAP!  (namespace=!NAMESPACE!, output=!OUTPUT!)
echo.

if /i "!OUTPUT!"=="data" (
    REM Just the .data map, one KEY=VALUE per line
    kubectl -n !NAMESPACE! get configmap !CONFIGMAP! -o jsonpath="{range .data}{@}{end}"
    echo.
    exit /b %errorlevel%
)

kubectl -n !NAMESPACE! get configmap !CONFIGMAP! -o !OUTPUT!
