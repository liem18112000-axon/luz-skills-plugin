#!/usr/bin/env bash
# Run a Cloud Build trigger by name. Linux/macOS counterpart of trigger_build.cmd.
#
# Required: TRIGGER_NAME (env var or 1st positional arg)
# Optional with org defaults (override any via env):
#   BUILD_PROJECT     default klara-infra
#   REGION            default europe-west6
#   BRANCH            default = current git branch (`git rev-parse --abbrev-ref HEAD`)
# Artifact Registry settings (used only for the "already-built" short-circuit):
#   ARTIFACT_PROJECT  default klara-repo
#   ARTIFACT_REGION   default europe-west6
#   ARTIFACT_REPO     default artifact-registry-container-images
#   ARTIFACT_IMAGE    default = TRIGGER_NAME
# Escape hatch:
#   FORCE=1           skip the "already-built" check and always run the trigger

set -euo pipefail

# Positional arg overrides env
if [[ $# -ge 1 && -n "$1" ]]; then
  TRIGGER_NAME=$1
fi

if [[ -z "${TRIGGER_NAME:-}" ]]; then
  echo "ERROR: TRIGGER_NAME is required (pass as 1st arg or env var)." >&2
  exit 1
fi

# ─── Org defaults ─────────────────────────────────────────────
BUILD_PROJECT=${BUILD_PROJECT:-klara-infra}
REGION=${REGION:-europe-west6}
ARTIFACT_PROJECT=${ARTIFACT_PROJECT:-klara-repo}
ARTIFACT_REGION=${ARTIFACT_REGION:-europe-west6}
ARTIFACT_REPO=${ARTIFACT_REPO:-artifact-registry-container-images}
ARTIFACT_IMAGE=${ARTIFACT_IMAGE:-$TRIGGER_NAME}

IMAGE_PATH="${ARTIFACT_REGION}-docker.pkg.dev/${ARTIFACT_PROJECT}/${ARTIFACT_REPO}/${ARTIFACT_IMAGE}"

# ─── Resolve BRANCH from current git branch if absent ────────
if [[ -z "${BRANCH:-}" ]]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: not in a git work tree; cannot infer BRANCH." >&2
    echo "       Pass BRANCH explicitly, e.g.  BRANCH=master $0" >&2
    exit 1
  fi
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$BRANCH" == "HEAD" ]]; then
    echo "ERROR: detached HEAD; cannot infer branch. Pass BRANCH explicitly." >&2
    exit 1
  fi
  echo "Using current git branch: $BRANCH"
fi

# ─── Skip if local HEAD SHA already exists as a tag ──────────
if [[ "${FORCE:-}" != "1" ]] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  CURRENT_SHA=$(git rev-parse HEAD)
  echo "Checking if $CURRENT_SHA already exists as a tag in $IMAGE_PATH ..."
  LATEST_TAG=$(gcloud artifacts docker images list "$IMAGE_PATH" \
                 --project="$ARTIFACT_PROJECT" \
                 --include-tags \
                 --sort-by="~UPDATE_TIME" \
                 --limit=1 \
                 --format="value(tags)" 2>/dev/null | tr -d '[:space:]' || true)

  if [[ -n "$LATEST_TAG" && "${LATEST_TAG,,}" == "${CURRENT_SHA,,}" ]]; then
    echo
    echo "Code is already in latest build."
    echo "  current SHA = $CURRENT_SHA"
    echo "  latest tag  = $LATEST_TAG"
    echo "Skipping. Set FORCE=1 to rebuild anyway."
    exit 0
  fi
  echo "  current SHA = $CURRENT_SHA"
  echo "  latest tag  = ${LATEST_TAG:-<none>}"
fi

# ─── Run ──────────────────────────────────────────────────────
echo
echo "Running Cloud Build trigger:"
echo "  name    = $TRIGGER_NAME"
echo "  project = $BUILD_PROJECT"
echo "  region  = $REGION"
echo "  branch  = $BRANCH"
echo

gcloud builds triggers run "$TRIGGER_NAME" \
  --project="$BUILD_PROJECT" \
  --region="$REGION" \
  --branch="$BRANCH"
