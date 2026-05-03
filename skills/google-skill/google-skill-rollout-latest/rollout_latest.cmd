@echo off
setlocal enabledelayedexpansion

REM ─── Inputs ───────────────────────────────────────────────────
REM Required:  STATEFULSET (env var) or 1st positional arg
REM Optional with org defaults (override any via env):
REM   ARTIFACT_PROJECT  default klara-repo
REM   ARTIFACT_REGION   default europe-west6
REM   ARTIFACT_REPO     default artifact-registry-container-images
REM   CLUSTER_PROJECT   default klara-nonprod
REM   CLUSTER_NAME      default klara-nonprod
REM   CLUSTER_ZONE      default europe-west6-a
REM   NAMESPACE         default dev
REM Conventional defaults (derived from STATEFULSET if not given):
REM   ARTIFACT_IMAGE    default = STATEFULSET
REM   CONTAINER         default = STATEFULSET

if not "%~1"=="" set STATEFULSET=%~1

if not defined STATEFULSET (
    echo ERROR: STATEFULSET is required (pass as 1st arg or env var^).
    exit /b 1
)

REM ─── Org defaults ─────────────────────────────────────────────
if not defined ARTIFACT_PROJECT set ARTIFACT_PROJECT=klara-repo
if not defined ARTIFACT_REGION  set ARTIFACT_REGION=europe-west6
if not defined ARTIFACT_REPO    set ARTIFACT_REPO=artifact-registry-container-images
if not defined CLUSTER_PROJECT  set CLUSTER_PROJECT=klara-nonprod
if not defined CLUSTER_NAME     set CLUSTER_NAME=klara-nonprod
if not defined CLUSTER_ZONE     set CLUSTER_ZONE=europe-west6-a
if not defined NAMESPACE        set NAMESPACE=dev

REM ─── Conventional defaults derived from STATEFULSET ───────────
if not defined ARTIFACT_IMAGE   set ARTIFACT_IMAGE=%STATEFULSET%
if not defined CONTAINER        set CONTAINER=%STATEFULSET%

set IMAGE_PATH=%ARTIFACT_REGION%-docker.pkg.dev/%ARTIFACT_PROJECT%/%ARTIFACT_REPO%/%ARTIFACT_IMAGE%

echo Resolved parameters:
echo   STATEFULSET      = %STATEFULSET%
echo   NAMESPACE        = %NAMESPACE%
echo   CONTAINER        = %CONTAINER%
echo   ARTIFACT_IMAGE   = %ARTIFACT_IMAGE%
echo   ARTIFACT_PROJECT = %ARTIFACT_PROJECT%
echo   ARTIFACT_REGION  = %ARTIFACT_REGION%
echo   ARTIFACT_REPO    = %ARTIFACT_REPO%
echo   CLUSTER_PROJECT  = %CLUSTER_PROJECT%
echo.

REM ─── (optional) refresh kubeconfig ────────────────────────────
REM Uncomment if the caller wants this script to switch context first.
REM gcloud container clusters get-credentials %CLUSTER_NAME% --zone=%CLUSTER_ZONE% --project=%CLUSTER_PROJECT%

REM ─── 1) Find the most recently uploaded tag ───────────────────
echo [1/5] Fetching latest tag from %IMAGE_PATH% ...
set LATEST_TAG=
for /f "delims=" %%i in ('gcloud artifacts docker images list %IMAGE_PATH% --project=%ARTIFACT_PROJECT% --include-tags --sort-by=~UPDATE_TIME --limit=1 --format="value(tags)"') do set LATEST_TAG=%%i

REM Strip any whitespace/CR from the captured value
for /f "tokens=* delims= " %%a in ("!LATEST_TAG!") do set LATEST_TAG=%%a

if "!LATEST_TAG!"=="" (
    echo ERROR: no tags returned from Artifact Registry.
    exit /b 1
)

echo Latest tag: !LATEST_TAG!

set NEW_IMAGE=%IMAGE_PATH%:!LATEST_TAG!

REM ─── 2) Show + capture image currently on the StatefulSet ────
echo.
echo [2/5] Current image on %NAMESPACE%/%STATEFULSET%:
set CURRENT_IMAGES=
for /f "delims=" %%i in ('kubectl -n %NAMESPACE% get statefulset/%STATEFULSET% -o jsonpath^="{.spec.template.spec.containers[*].image}"') do set CURRENT_IMAGES=%%i
echo !CURRENT_IMAGES!

REM ─── If target image already deployed, just rollout restart ──
echo !CURRENT_IMAGES! | findstr /l /c:"!NEW_IMAGE!" >nul
if not errorlevel 1 (
    echo.
    echo [3/5] Image already at latest tag !LATEST_TAG!.
    echo        Restarting rollout to refresh pods (no spec or annotation change^).
    kubectl -n %NAMESPACE% rollout restart statefulset/%STATEFULSET%
    if errorlevel 1 (
        echo ERROR: kubectl rollout restart failed.
        exit /b 1
    )
    goto :wait_rollout
)

REM ─── 3) Patch the StatefulSet spec ────────────────────────────
echo.
echo [3/5] Setting spec image to: !NEW_IMAGE!
kubectl -n %NAMESPACE% set image statefulset/%STATEFULSET% %CONTAINER%=!NEW_IMAGE!
if errorlevel 1 (
    echo ERROR: kubectl set image failed.
    exit /b 1
)

REM ─── 4) Sync last-applied-configuration annotation ───────────
REM kubectl set image only mutates spec.template.spec.containers[*].image.
REM The kubectl.kubernetes.io/last-applied-configuration annotation still
REM holds the previous tag, so any later "kubectl apply" would compute a
REM bogus diff. Rewrite just the <ARTIFACT_IMAGE> tag inside that JSON
REM blob and re-annotate. Other images in the annotation are untouched.
echo.
echo [4/5] Updating last-applied-configuration annotation...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ns='%NAMESPACE%'; $sts='%STATEFULSET%'; $img='%ARTIFACT_IMAGE%'; $tag='!LATEST_TAG!';" ^
  "$ann = & kubectl -n $ns get statefulset/$sts -o 'jsonpath={.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}';" ^
  "if ([string]::IsNullOrEmpty($ann)) { Write-Host 'No last-applied-configuration annotation present, skipping.'; exit 0 }" ^
  "$pattern = '/' + [regex]::Escape($img) + ':[A-Za-z0-9_.\-]+';" ^
  "$updated = [regex]::Replace($ann, $pattern, ('/' + $img + ':' + $tag));" ^
  "if ($updated -eq $ann) { Write-Host 'Annotation already in sync.'; exit 0 }" ^
  "$payload = 'kubectl.kubernetes.io/last-applied-configuration=' + $updated;" ^
  "& kubectl -n $ns annotate statefulset/$sts --overwrite $payload | Out-Null;" ^
  "if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }"
if errorlevel 1 (
    echo ERROR: failed to update last-applied-configuration annotation.
    exit /b 1
)

:wait_rollout
REM ─── 5) Wait for rollout ──────────────────────────────────────
echo.
echo [5/5] Waiting for rollout to complete...
kubectl -n %NAMESPACE% rollout status statefulset/%STATEFULSET% --timeout=600s
exit /b %errorlevel%
