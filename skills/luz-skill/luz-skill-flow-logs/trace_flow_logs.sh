#!/usr/bin/env bash
# Read interleaved Cloud Logging entries across the Luz request flow:
#   luz-webclient -> luz-docs-view-controller -> luz-docs -> luz-jsonstore
#
# A single `gcloud logging read` call with a multi-container OR filter,
# so entries from all 4 services come back in chronological order and
# can be reasoned about as one trace.
#
# This is the multi-service counterpart of `google-skill-gke-logs` (which
# reads a single container). Reuse that skill when you only need one
# service; reach for this one when correlating across the chain.
#
# Required (highly recommended): SEARCH (substring on textPayload — usually
# a tenant id or request id). Without it the call is rate-limited noise.
#
# Optional with org defaults (override any via env):
#   NAMESPACE        default dev
#   CLUSTER_NAME     default klara-nonprod
#   CLUSTER_PROJECT  default klara-nonprod
#   LIMIT            default 5000  (split across the 4 services)
#   FRESHNESS        default 30m
#   SEVERITY         keep severity >= this value (e.g. ERROR)
#   SERVICES         comma-list, default
#                    luz-webclient,luz-docs-view-controller,luz-docs,luz-jsonstore

set -euo pipefail

# Positional arg overrides SEARCH env
if [[ $# -ge 1 && -n "$1" ]]; then
  SEARCH=$1
fi

# ─── Org defaults ─────────────────────────────────────────────
CLUSTER_PROJECT=${CLUSTER_PROJECT:-klara-nonprod}
CLUSTER_NAME=${CLUSTER_NAME:-klara-nonprod}
NAMESPACE=${NAMESPACE:-dev}
LIMIT=${LIMIT:-5000}
FRESHNESS=${FRESHNESS:-30m}
SERVICES=${SERVICES:-luz-webclient,luz-docs-view-controller,luz-docs,luz-jsonstore}

# ─── Build container OR clause ────────────────────────────────
IFS=',' read -ra SERVICE_LIST <<< "$SERVICES"
CONTAINER_CLAUSE=""
for svc in "${SERVICE_LIST[@]}"; do
  svc_trim=$(echo "$svc" | tr -d '[:space:]')
  [[ -z "$svc_trim" ]] && continue
  if [[ -z "$CONTAINER_CLAUSE" ]]; then
    CONTAINER_CLAUSE="resource.labels.container_name=$svc_trim"
  else
    CONTAINER_CLAUSE="$CONTAINER_CLAUSE OR resource.labels.container_name=$svc_trim"
  fi
done

# ─── Build full filter ────────────────────────────────────────
FILTER="resource.type=k8s_container"
FILTER="$FILTER AND resource.labels.cluster_name=$CLUSTER_NAME"
FILTER="$FILTER AND resource.labels.namespace_name=$NAMESPACE"
FILTER="$FILTER AND ($CONTAINER_CLAUSE)"

if [[ -n "${SEVERITY:-}" ]]; then FILTER="$FILTER AND severity>=$SEVERITY"; fi
if [[ -n "${SEARCH:-}" ]];   then FILTER="$FILTER AND textPayload:$SEARCH"; fi

cat <<EOF
Reading Cloud Logging entries across Luz flow:
  project   = $CLUSTER_PROJECT
  cluster   = $CLUSTER_NAME
  namespace = $NAMESPACE
  services  = $SERVICES
  freshness = $FRESHNESS
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
