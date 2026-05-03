#!/usr/bin/env bash
# Read Cloud Logging entries for a GKE container. Linux/macOS counterpart of view_logs.cmd.
#
# Required: CONTAINER (env var or 1st positional arg)
# Optional with org defaults (override any via env):
#   NAMESPACE        default dev
#   CLUSTER_NAME     default klara-nonprod
#   CLUSTER_PROJECT  default klara-nonprod
#   LIMIT            default 2000
#   FRESHNESS        default 30m
# Filter add-ons (each appended to the query when set):
#   POD              filter by pod name
#   SEVERITY         keep severity >= this value (e.g. ERROR)
#   SEARCH           substring match on textPayload

set -euo pipefail

# Positional arg overrides env
if [[ $# -ge 1 && -n "$1" ]]; then
  CONTAINER=$1
fi

if [[ -z "${CONTAINER:-}" ]]; then
  echo "ERROR: CONTAINER is required (pass as 1st arg or env var)." >&2
  echo "       Example: $0 luz-docs" >&2
  exit 1
fi

# ─── Org defaults ─────────────────────────────────────────────
CLUSTER_PROJECT=${CLUSTER_PROJECT:-klara-nonprod}
CLUSTER_NAME=${CLUSTER_NAME:-klara-nonprod}
NAMESPACE=${NAMESPACE:-dev}
LIMIT=${LIMIT:-2000}
FRESHNESS=${FRESHNESS:-30m}

# ─── Build filter ─────────────────────────────────────────────
FILTER="resource.type=k8s_container"
FILTER="$FILTER AND resource.labels.cluster_name=$CLUSTER_NAME"
FILTER="$FILTER AND resource.labels.namespace_name=$NAMESPACE"
FILTER="$FILTER AND resource.labels.container_name=$CONTAINER"

if [[ -n "${POD:-}" ]];      then FILTER="$FILTER AND resource.labels.pod_name=$POD"; fi
if [[ -n "${SEVERITY:-}" ]]; then FILTER="$FILTER AND severity>=$SEVERITY"; fi
if [[ -n "${SEARCH:-}" ]];   then FILTER="$FILTER AND textPayload:$SEARCH"; fi

cat <<EOF
Reading Cloud Logging entries:
  project   = $CLUSTER_PROJECT
  cluster   = $CLUSTER_NAME
  namespace = $NAMESPACE
  container = $CONTAINER
${POD:+  pod       = $POD
}  freshness = $FRESHNESS
  limit     = $LIMIT
${SEVERITY:+  severity  = >=$SEVERITY
}${SEARCH:+  search    = $SEARCH
}
EOF

gcloud logging read "$FILTER" \
  --project="$CLUSTER_PROJECT" \
  --limit="$LIMIT" \
  --freshness="$FRESHNESS" \
  --order=desc
