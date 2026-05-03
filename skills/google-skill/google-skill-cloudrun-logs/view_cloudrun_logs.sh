#!/usr/bin/env bash
# Read Cloud Logging entries for a Cloud Run service. Linux/macOS counterpart of view_cloudrun_logs.cmd.
#
# Required: SERVICE (env var or 1st positional arg)
# Optional with org defaults (override any via env):
#   PROJECT     default klara-nonprod
#   REGION      default europe-west6
#   LIMIT       default 2000
#   FRESHNESS   default 30m
# Filter add-ons (each appended to the query when set):
#   REVISION    filter by revision name
#   SEVERITY    keep severity >= this value (e.g. ERROR)
#   SEARCH      substring match on textPayload

set -euo pipefail

# Positional arg overrides env
if [[ $# -ge 1 && -n "$1" ]]; then
  SERVICE=$1
fi

if [[ -z "${SERVICE:-}" ]]; then
  echo "ERROR: SERVICE is required (pass as 1st arg or env var)." >&2
  echo "       Example: $0 dev-luz-thumbnail" >&2
  exit 1
fi

# ─── Org defaults ─────────────────────────────────────────────
PROJECT=${PROJECT:-klara-nonprod}
REGION=${REGION:-europe-west6}
LIMIT=${LIMIT:-2000}
FRESHNESS=${FRESHNESS:-30m}

# ─── Build filter ─────────────────────────────────────────────
FILTER="resource.type=cloud_run_revision"
FILTER="$FILTER AND resource.labels.service_name=$SERVICE"
FILTER="$FILTER AND resource.labels.location=$REGION"

if [[ -n "${REVISION:-}" ]]; then FILTER="$FILTER AND resource.labels.revision_name=$REVISION"; fi
if [[ -n "${SEVERITY:-}" ]]; then FILTER="$FILTER AND severity>=$SEVERITY"; fi
if [[ -n "${SEARCH:-}" ]];   then FILTER="$FILTER AND textPayload:$SEARCH"; fi

cat <<EOF
Reading Cloud Run logs:
  project   = $PROJECT
  service   = $SERVICE
  region    = $REGION
${REVISION:+  revision  = $REVISION
}  freshness = $FRESHNESS
  limit     = $LIMIT
${SEVERITY:+  severity  = >=$SEVERITY
}${SEARCH:+  search    = $SEARCH
}
EOF

gcloud logging read "$FILTER" \
  --project="$PROJECT" \
  --limit="$LIMIT" \
  --freshness="$FRESHNESS" \
  --order=desc
