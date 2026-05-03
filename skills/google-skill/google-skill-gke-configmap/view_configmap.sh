#!/usr/bin/env bash
# View a Kubernetes ConfigMap. Linux/macOS counterpart of view_configmap.cmd.
#
# Required: CONFIGMAP (env var or 1st positional arg)
# Optional:
#   NAMESPACE   default dev
#   OUTPUT      default yaml (alternatives: json, data)

set -euo pipefail

if [[ $# -ge 1 && -n "$1" ]]; then
  CONFIGMAP=$1
fi

if [[ -z "${CONFIGMAP:-}" ]]; then
  echo "ERROR: CONFIGMAP is required (pass as 1st arg or env var)." >&2
  echo "       Example: $0 luz-docs-env-configmap-h7h69gmbt2" >&2
  exit 1
fi

NAMESPACE=${NAMESPACE:-dev}
OUTPUT=${OUTPUT:-yaml}

echo "ConfigMap: $CONFIGMAP  (namespace=$NAMESPACE, output=$OUTPUT)"
echo

case "$OUTPUT" in
  data)
    # Just the .data map, one KEY=VALUE per line (sorted).
    kubectl -n "$NAMESPACE" get configmap "$CONFIGMAP" \
      -o go-template='{{range $k, $v := .data}}{{$k}}={{$v}}{{"\n"}}{{end}}' \
      | sort
    ;;
  *)
    kubectl -n "$NAMESPACE" get configmap "$CONFIGMAP" -o "$OUTPUT"
    ;;
esac
