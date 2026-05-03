#!/usr/bin/env bash
# Roll a StatefulSet container to the most recent image tag in Google Artifact Registry.
# Linux / macOS counterpart of rollout_latest.cmd.
#
# Required: STATEFULSET (env var or 1st positional arg)
# Optional with org defaults (override any via env):
#   ARTIFACT_PROJECT  default klara-repo
#   ARTIFACT_REGION   default europe-west6
#   ARTIFACT_REPO     default artifact-registry-container-images
#   CLUSTER_PROJECT   default klara-nonprod
#   CLUSTER_NAME      default klara-nonprod
#   CLUSTER_ZONE      default europe-west6-a
#   NAMESPACE         default dev
# Conventional defaults (derived from STATEFULSET if not given):
#   ARTIFACT_IMAGE    default = STATEFULSET
#   CONTAINER         default = STATEFULSET

set -euo pipefail

# Positional arg overrides env
if [[ $# -ge 1 && -n "$1" ]]; then
  STATEFULSET=$1
fi

if [[ -z "${STATEFULSET:-}" ]]; then
  echo "ERROR: STATEFULSET is required (pass as 1st arg or env var)." >&2
  exit 1
fi

# ─── Org defaults ─────────────────────────────────────────────
ARTIFACT_PROJECT=${ARTIFACT_PROJECT:-klara-repo}
ARTIFACT_REGION=${ARTIFACT_REGION:-europe-west6}
ARTIFACT_REPO=${ARTIFACT_REPO:-artifact-registry-container-images}
CLUSTER_PROJECT=${CLUSTER_PROJECT:-klara-nonprod}
CLUSTER_NAME=${CLUSTER_NAME:-klara-nonprod}
CLUSTER_ZONE=${CLUSTER_ZONE:-europe-west6-a}
NAMESPACE=${NAMESPACE:-dev}

# ─── Conventional defaults derived from STATEFULSET ───────────
ARTIFACT_IMAGE=${ARTIFACT_IMAGE:-$STATEFULSET}
CONTAINER=${CONTAINER:-$STATEFULSET}

IMAGE_PATH="${ARTIFACT_REGION}-docker.pkg.dev/${ARTIFACT_PROJECT}/${ARTIFACT_REPO}/${ARTIFACT_IMAGE}"

cat <<EOF
Resolved parameters:
  STATEFULSET      = $STATEFULSET
  NAMESPACE        = $NAMESPACE
  CONTAINER        = $CONTAINER
  ARTIFACT_IMAGE   = $ARTIFACT_IMAGE
  ARTIFACT_PROJECT = $ARTIFACT_PROJECT
  ARTIFACT_REGION  = $ARTIFACT_REGION
  ARTIFACT_REPO    = $ARTIFACT_REPO
  CLUSTER_PROJECT  = $CLUSTER_PROJECT

EOF

# ─── (optional) refresh kubeconfig ────────────────────────────
# Uncomment if the caller wants this script to switch context first.
# gcloud container clusters get-credentials "$CLUSTER_NAME" \
#   --zone="$CLUSTER_ZONE" --project="$CLUSTER_PROJECT"

# ─── 1) Find the most recently uploaded tag ───────────────────
echo "[1/5] Fetching latest tag from $IMAGE_PATH ..."
LATEST_TAG=$(gcloud artifacts docker images list "$IMAGE_PATH" \
    --project="$ARTIFACT_PROJECT" \
    --include-tags \
    --sort-by="~UPDATE_TIME" \
    --limit=1 \
    --format="value(tags)" | tr -d '[:space:]')

if [[ -z "$LATEST_TAG" ]]; then
  echo "ERROR: no tags returned from Artifact Registry." >&2
  exit 1
fi
echo "Latest tag: $LATEST_TAG"

NEW_IMAGE="${IMAGE_PATH}:${LATEST_TAG}"

# ─── 2) Show + capture image currently on the StatefulSet ────
echo
echo "[2/5] Current image on ${NAMESPACE}/${STATEFULSET}:"
CURRENT_IMAGES=$(kubectl -n "$NAMESPACE" get "statefulset/${STATEFULSET}" \
  -o jsonpath='{.spec.template.spec.containers[*].image}')
echo "$CURRENT_IMAGES"

# ─── If target image already deployed, just rollout restart ──
if [[ "$CURRENT_IMAGES" == *"$NEW_IMAGE"* ]]; then
  echo
  echo "[3/5] Image already at latest tag ${LATEST_TAG}."
  echo "       Restarting rollout to refresh pods (no spec or annotation change)."
  kubectl -n "$NAMESPACE" rollout restart "statefulset/${STATEFULSET}"

  echo
  echo "[5/5] Waiting for rollout to complete..."
  kubectl -n "$NAMESPACE" rollout status "statefulset/${STATEFULSET}" --timeout=600s
  exit $?
fi

# ─── 3) Patch the StatefulSet spec ────────────────────────────
echo
echo "[3/5] Setting spec image to: $NEW_IMAGE"
kubectl -n "$NAMESPACE" set image "statefulset/${STATEFULSET}" "${CONTAINER}=${NEW_IMAGE}"

# ─── 4) Sync last-applied-configuration annotation ───────────
# kubectl set image only mutates spec.template.spec.containers[*].image.
# The kubectl.kubernetes.io/last-applied-configuration annotation still holds
# the previous tag, so any later "kubectl apply" would compute a bogus diff.
# Rewrite just the <ARTIFACT_IMAGE> tag inside that JSON blob and re-annotate.
# Other images in the annotation are untouched.
echo
echo "[4/5] Updating last-applied-configuration annotation..."
ANN=$(kubectl -n "$NAMESPACE" get "statefulset/${STATEFULSET}" \
  -o "jsonpath={.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}")

if [[ -z "$ANN" ]]; then
  echo "No last-applied-configuration annotation present, skipping."
else
  # Escape regex meta-chars in the image name so the substitution stays anchored.
  IMG_ESC=$(printf '%s' "$ARTIFACT_IMAGE" | sed -e 's/[][\.*+?^$(){}|/]/\\&/g')
  UPDATED=$(printf '%s' "$ANN" | sed -E "s|/${IMG_ESC}:[A-Za-z0-9_.-]+|/${ARTIFACT_IMAGE}:${LATEST_TAG}|g")

  if [[ "$UPDATED" == "$ANN" ]]; then
    echo "Annotation already in sync."
  else
    kubectl -n "$NAMESPACE" annotate "statefulset/${STATEFULSET}" --overwrite \
      "kubectl.kubernetes.io/last-applied-configuration=${UPDATED}" >/dev/null
    echo "Annotation updated."
  fi
fi

# ─── 5) Wait for rollout ──────────────────────────────────────
echo
echo "[5/5] Waiting for rollout to complete..."
kubectl -n "$NAMESPACE" rollout status "statefulset/${STATEFULSET}" --timeout=600s
