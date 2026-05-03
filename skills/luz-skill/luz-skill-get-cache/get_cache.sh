#!/usr/bin/env bash
# Fetch a Luz cache entry via the api-forwarder.
#
# Required:
#   TENANT_ID    1st positional or env  (e.g. be01bf45-611a-4011-90a8-76227db1d190)
#   CACHE_KEY    2nd positional or env  (e.g. CustomerIdAndEmaiMap)
#
# Optional with defaults (override via env):
#   NAMESPACE         default 'dev'
#   PORT              default 8080  (starting local port — auto-increments if busy)
#   REMOTE_PORT       default 8080  (api-forwarder service port; never increments)
#   MAX_PORT_ATTEMPTS default 10    (max consecutive ports to try)
#   HOST              default localhost
#   TOKEN             unset → auto-acquired via luz-skill-get-token (needs ADMIN_TENANT_ID)
#   ADMIN_TENANT_ID   required when TOKEN unset
#   TOKEN_PREFIX      default 'Bearer ' (set TOKEN_PREFIX='' to send raw token)
#   BASIC_AUTH        default 'YWRtaW46YWRtaW4='   (forwarded to token skill)

set -euo pipefail

if [[ $# -ge 1 && -n "$1" ]]; then TENANT_ID=$1; fi
if [[ $# -ge 2 && -n "$2" ]]; then CACHE_KEY=$2; fi

if [[ -z "${TENANT_ID:-}" || -z "${CACHE_KEY:-}" ]]; then
  echo "ERROR: TENANT_ID and CACHE_KEY are required." >&2
  echo "  Usage: $0 <TENANT_ID> <CACHE_KEY>" >&2
  echo "  Example: $0 be01bf45-611a-4011-90a8-76227db1d190 CustomerIdAndEmaiMap" >&2
  exit 1
fi

NAMESPACE=${NAMESPACE:-dev}
PORT=${PORT:-8080}
REMOTE_PORT=${REMOTE_PORT:-8080}
MAX_PORT_ATTEMPTS=${MAX_PORT_ATTEMPTS:-10}
HOST=${HOST:-localhost}
BASIC_AUTH=${BASIC_AUTH:-YWRtaW46YWRtaW4=}
TOKEN_PREFIX=${TOKEN_PREFIX-Bearer }

# ─── Connectivity probe via /dev/tcp ────────────────────────
is_port_open() {
  (exec 3<>"/dev/tcp/$1/$2") >/dev/null 2>&1 && exec 3<&- 3>&-
}

ensure_port_forward() {
  local start_port=$PORT
  local attempt
  for ((attempt=0; attempt<MAX_PORT_ATTEMPTS; attempt++)); do
    PORT=$((start_port + attempt))

    if is_port_open "$HOST" "$PORT"; then
      echo "[luz-cache] $HOST:$PORT already reachable — reusing." >&2
      return 0
    fi

    echo "[luz-cache] launching port-forward local:$PORT -> svc:api-forwarder:$REMOTE_PORT (ns=$NAMESPACE)..." >&2
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
      echo "[luz-cache] port-forward ready on local port $PORT (pid=$pid log=$logfile)" >&2
      return 0
    fi

    kill "$pid" 2>/dev/null || true

    if grep -qiE "address already in use|unable to listen|bind:" "$logfile" 2>/dev/null; then
      echo "[luz-cache]   port $PORT busy — trying $((PORT+1))..." >&2
      continue
    fi

    echo "[luz-cache] ERROR: port-forward on $PORT failed — see $logfile" >&2
    cat "$logfile" >&2 2>/dev/null || true
    return 1
  done

  echo "[luz-cache] ERROR: tried $MAX_PORT_ATTEMPTS ports starting at $start_port — none worked." >&2
  return 1
}

ensure_port_forward

# ─── Acquire token if not provided ───────────────────────────
if [[ -z "${TOKEN:-}" ]]; then
  if [[ -z "${ADMIN_TENANT_ID:-}" ]]; then
    echo "[luz-cache] ERROR: TOKEN not set and ADMIN_TENANT_ID missing — cannot authenticate." >&2
    echo "             Pass TOKEN=... or ADMIN_TENANT_ID=..." >&2
    exit 2
  fi
  TOKEN_SCRIPT="$(dirname "$0")/../luz-skill-get-token/get_token.sh"
  if [[ ! -x "$TOKEN_SCRIPT" ]]; then
    # On Windows checkouts the file may be present without +x bit.
    if [[ -f "$TOKEN_SCRIPT" ]]; then
      chmod +x "$TOKEN_SCRIPT" 2>/dev/null || true
    fi
  fi
  if [[ ! -f "$TOKEN_SCRIPT" ]]; then
    echo "[luz-cache] ERROR: companion script not found at $TOKEN_SCRIPT" >&2
    exit 2
  fi
  echo "[luz-cache] Acquiring token via luz-skill-get-token..." >&2
  TOKEN=$(NAMESPACE="$NAMESPACE" PORT="$PORT" HOST="$HOST" BASIC_AUTH="$BASIC_AUTH" \
    bash "$TOKEN_SCRIPT" "$ADMIN_TENANT_ID")
fi

# ─── GET the cache entry ─────────────────────────────────────
URL="http://${HOST}:${PORT}/luz_cache/api/${TENANT_ID}/${CACHE_KEY}"
echo "[luz-cache] GET $URL" >&2

BODY_FILE=$(mktemp -t luz-cache-XXXXXX)
trap 'rm -f "$BODY_FILE"' EXIT

HTTP_CODE=$(curl -sS -o "$BODY_FILE" -w "%{http_code}" \
  --location "$URL" \
  --header "Authorization: ${TOKEN_PREFIX}${TOKEN}")

echo "[luz-cache] HTTP $HTTP_CODE" >&2

if [[ "$HTTP_CODE" == "404" ]]; then
  echo "not found"
  exit 0
fi

BODY=$(cat "$BODY_FILE")
TRIMMED=$(printf '%s' "$BODY" | tr -d '[:space:]')

if [[ -z "$TRIMMED" || "$TRIMMED" == "null" ]]; then
  echo "not found"
  exit 0
fi

if [[ "$HTTP_CODE" != 2* ]]; then
  echo "[luz-cache] WARN: non-2xx response ($HTTP_CODE) — body follows" >&2
fi

# Pretty-print JSON if possible, else dump verbatim.
if printf '%s' "$BODY" | python3 -c "import json,sys; json.load(sys.stdin)" >/dev/null 2>&1; then
  printf '%s' "$BODY" | python3 -m json.tool
else
  printf '%s\n' "$BODY"
fi
