#!/usr/bin/env bash
# Acquire a Luz all-tenant access token via the api-forwarder.
#
# Required: ADMIN_TENANT_ID (env var or 1st positional arg)
# Optional with defaults (override via env):
#   NAMESPACE           default 'dev'
#   PORT                default 8080  (starting local port — auto-increments if busy)
#   REMOTE_PORT         default 8080  (api-forwarder service port; never increments)
#   MAX_PORT_ATTEMPTS   default 10    (max consecutive ports to try)
#   HOST                default localhost
#   BASIC_AUTH          default 'YWRtaW46YWRtaW4='   (admin:admin)
#
# stdout: the token value (and nothing else) on success.
# stderr: status messages, including the resolved local port.

set -euo pipefail

if [[ $# -ge 1 && -n "$1" ]]; then
  ADMIN_TENANT_ID=$1
fi

if [[ -z "${ADMIN_TENANT_ID:-}" ]]; then
  echo "ERROR: ADMIN_TENANT_ID is required (1st arg or env var)." >&2
  echo "       Example: $0 00a04daf-f2b3-41d5-8c12-2d1b4c48a36a" >&2
  exit 1
fi

NAMESPACE=${NAMESPACE:-dev}
PORT=${PORT:-8080}
REMOTE_PORT=${REMOTE_PORT:-8080}
MAX_PORT_ATTEMPTS=${MAX_PORT_ATTEMPTS:-10}
HOST=${HOST:-localhost}
BASIC_AUTH=${BASIC_AUTH:-YWRtaW46YWRtaW4=}

# ─── Connectivity probe via bash /dev/tcp ────────────────────
is_port_open() {
  (exec 3<>"/dev/tcp/$1/$2") >/dev/null 2>&1 && exec 3<&- 3>&-
}

ensure_port_forward() {
  local start_port=$PORT
  local attempt
  for ((attempt=0; attempt<MAX_PORT_ATTEMPTS; attempt++)); do
    PORT=$((start_port + attempt))

    if is_port_open "$HOST" "$PORT"; then
      echo "[luz-token] $HOST:$PORT already reachable — reusing." >&2
      return 0
    fi

    echo "[luz-token] launching port-forward local:$PORT -> svc:api-forwarder:$REMOTE_PORT (ns=$NAMESPACE)..." >&2
    local logfile="/tmp/luz-portforward-${NAMESPACE}-${PORT}.log"
    : >"$logfile" 2>/dev/null || true
    nohup kubectl port-forward --address 0.0.0.0 \
      "services/api-forwarder" "${PORT}:${REMOTE_PORT}" \
      -n "$NAMESPACE" \
      >"$logfile" 2>&1 &
    local pid=$!
    disown 2>/dev/null || true

    local ready=0 i
    for i in 1 2 3 4 5 6 7; do
      sleep 1
      if is_port_open "$HOST" "$PORT"; then
        ready=1; break
      fi
      if ! kill -0 "$pid" 2>/dev/null; then
        break  # kubectl exited (most likely a bind failure)
      fi
    done

    if (( ready )); then
      echo "[luz-token] port-forward ready on local port $PORT (pid=$pid log=$logfile)" >&2
      return 0
    fi

    kill "$pid" 2>/dev/null || true

    if grep -qiE "address already in use|unable to listen|bind:" "$logfile" 2>/dev/null; then
      echo "[luz-token]   port $PORT busy — trying $((PORT+1))..." >&2
      continue
    fi

    echo "[luz-token] ERROR: port-forward on $PORT failed — see $logfile" >&2
    cat "$logfile" >&2 2>/dev/null || true
    return 1
  done

  echo "[luz-token] ERROR: tried $MAX_PORT_ATTEMPTS ports starting at $start_port — none worked." >&2
  return 1
}

ensure_port_forward

URL="http://${HOST}:${PORT}/luzsec/api/${ADMIN_TENANT_ID}/access/tokens?type=all-tenant"
echo "[luz-token] POST $URL" >&2

RESP=$(curl -sS --location --request POST "$URL" \
  --header "Authorization: Basic ${BASIC_AUTH}")

TOKEN=$(printf '%s' "$RESP" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception as e:
    sys.stderr.write(f"[luz-token] ERROR: response was not JSON: {e}\n")
    sys.exit(2)
tok = data.get("token")
if not tok:
    sys.stderr.write(f"[luz-token] ERROR: no \"token\" field in response. Body: {json.dumps(data)[:500]}\n")
    sys.exit(3)
print(tok)
')

printf '%s\n' "$TOKEN"
