@echo off
setlocal enabledelayedexpansion

REM ─── Inputs ───────────────────────────────────────────────────
REM Required:  TRIGGER_NAME (env var) or 1st positional arg
REM Optional with org defaults (override any via env):
REM   BUILD_PROJECT     default klara-infra
REM   REGION            default europe-west6
REM   BRANCH            default = current git branch (`git rev-parse --abbrev-ref HEAD`)
REM Artifact Registry settings (used only for the "already-built" short-circuit):
REM   ARTIFACT_PROJECT  default klara-repo
REM   ARTIFACT_REGION   default europe-west6
REM   ARTIFACT_REPO     default artifact-registry-container-images
REM   ARTIFACT_IMAGE    default = TRIGGER_NAME
REM Escape hatch:
REM   FORCE=1           skip the "already-built" check and always run the trigger

if not "%~1"=="" set TRIGGER_NAME=%~1

if not defined TRIGGER_NAME (
    echo ERROR: TRIGGER_NAME is required (pass as 1st arg or env var^).
    exit /b 1
)

REM ─── Org defaults ─────────────────────────────────────────────
if not defined BUILD_PROJECT     set BUILD_PROJECT=klara-infra
if not defined REGION            set REGION=europe-west6
if not defined ARTIFACT_PROJECT  set ARTIFACT_PROJECT=klara-repo
if not defined ARTIFACT_REGION   set ARTIFACT_REGION=europe-west6
if not defined ARTIFACT_REPO     set ARTIFACT_REPO=artifact-registry-container-images
if not defined ARTIFACT_IMAGE    set ARTIFACT_IMAGE=%TRIGGER_NAME%

set IMAGE_PATH=%ARTIFACT_REGION%-docker.pkg.dev/%ARTIFACT_PROJECT%/%ARTIFACT_REPO%/%ARTIFACT_IMAGE%

REM ─── Resolve BRANCH from current git branch if absent ────────
if defined BRANCH goto :branch_resolved
git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo ERROR: not in a git work tree; cannot infer BRANCH.
    echo        Pass BRANCH explicitly, e.g.  set BRANCH=master
    exit /b 1
)
for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD') do set BRANCH=%%b
if "!BRANCH!"=="HEAD" (
    echo ERROR: detached HEAD; cannot infer branch. Pass BRANCH explicitly.
    exit /b 1
)
echo Using current git branch: !BRANCH!
:branch_resolved

REM ─── Skip if local HEAD SHA already exists as a tag ──────────
if "%FORCE%"=="1" goto :run_trigger
git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 goto :run_trigger

set CURRENT_SHA=
for /f "delims=" %%s in ('git rev-parse HEAD') do set CURRENT_SHA=%%s
if "!CURRENT_SHA!"=="" goto :run_trigger

echo Checking if !CURRENT_SHA! already exists as a tag in %IMAGE_PATH% ...
set LATEST_TAG=
for /f "delims=" %%t in ('gcloud artifacts docker images list %IMAGE_PATH% --project^=%ARTIFACT_PROJECT% --include-tags --sort-by^=~UPDATE_TIME --limit^=1 --format^="value(tags)" 2^>nul') do set LATEST_TAG=%%t
for /f "tokens=* delims= " %%a in ("!LATEST_TAG!") do set LATEST_TAG=%%a

if /i "!LATEST_TAG!"=="!CURRENT_SHA!" (
    echo.
    echo Code is already in latest build.
    echo   current SHA = !CURRENT_SHA!
    echo   latest tag  = !LATEST_TAG!
    echo Skipping. Set FORCE=1 to rebuild anyway.
    exit /b 0
)
echo   current SHA = !CURRENT_SHA!
echo   latest tag  = !LATEST_TAG!

:run_trigger
echo.
echo Running Cloud Build trigger:
echo   name    = !TRIGGER_NAME!
echo   project = !BUILD_PROJECT!
echo   region  = !REGION!
echo   branch  = !BRANCH!
echo.

gcloud builds triggers run !TRIGGER_NAME! ^
  --project=!BUILD_PROJECT! ^
  --region=!REGION! ^
  --branch=!BRANCH!
exit /b %errorlevel%
