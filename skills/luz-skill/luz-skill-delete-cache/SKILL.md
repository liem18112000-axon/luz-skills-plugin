---
name: luz-skill-delete-cache
description: Delete (evict) a Luz cache entry from the luz_cache service for a given tenant + cache key, via the api-forwarder in GKE. Use when the user asks to "evict cache <key>", "delete luz cache <key>", "invalidate CustomerIdAndEmaiMap for tenant <id>", or "drop the cache entry". Same endpoint as luz-skill-get-cache but uses HTTP DELETE. Auto-starts a `kubectl port-forward` to `services/api-forwarder` on the chosen namespace if `localhost:PORT` is not already reachable, auto-increments the local port (8080 → 8081 → …) when the requested port is occupied, and auto-acquires an admin token when one is not supplied. Prints `deleted` on 2xx, or `not found` if the API returns 404. Bash-only; Windows users run via Git Bash or `bash` from PowerShell (one-time `ensure-bash.ps1` bootstrap).
---

# luz-skill-delete-cache

Wraps `DELETE /luz_cache/api/{TENANT_ID}/{CACHE_KEY}`. Same connectivity / token-acquisition flow as `luz-skill-get-cache`, only the HTTP verb changes. Because this mutates server state, the script always echoes the resolved tuple to stderr before firing the request.

## Inputs

| Var | Required? | Default |
| --- | --- | --- |
| `TENANT_ID`         | **yes** | (none — 1st positional arg, e.g. `be01bf45-611a-4011-90a8-76227db1d190`) |
| `CACHE_KEY`         | **yes** | (none — 2nd positional arg, e.g. `CustomerIdAndEmaiMap`) |
| `NAMESPACE`         | optional | `dev` |
| `PORT`              | optional | `8080` (starting local port — auto-increments if busy) |
| `REMOTE_PORT`       | optional | `8080` (api-forwarder service port — never increments) |
| `MAX_PORT_ATTEMPTS` | optional | `10` (max consecutive ports to try) |
| `HOST`              | optional | `localhost` |
| `TOKEN`             | optional | unset → auto-acquired via luz-skill-get-token (needs `ADMIN_TENANT_ID`) |
| `ADMIN_TENANT_ID`   | optional | required only when `TOKEN` is unset |
| `TOKEN_PREFIX`      | optional | `Bearer ` (set to empty string to send the raw token) |
| `BASIC_AUTH`        | optional | `YWRtaW46YWRtaW4=` (forwarded to the token skill) |

## How to gather inputs

1. Parse `KEY=VALUE` args. Accept the first two bare positionals as `TENANT_ID` then `CACHE_KEY`.
2. **Always** ask for `TENANT_ID` and `CACHE_KEY` if missing — this skill mutates state, so never guess.
3. If neither `TOKEN` nor `ADMIN_TENANT_ID` is provided, ask the user which one to use (you cannot auth without one).
4. Confirm the deletion target (tenant + cache key + namespace) before running, since the call is destructive.
5. Don't prompt for the rest — apply defaults.

## How to invoke

### Invocation (bash)

Path: `~/.claude/skills/luz-skill-delete-cache/delete_cache.sh`

Linux / macOS: run directly. Windows: run via Git Bash, or invoke from PowerShell as `bash ~/.claude/skills/luz-skill-delete-cache/delete_cache.sh ARGS`.

First-time Windows setup (only if `bash` is not on PATH yet):
`powershell -ExecutionPolicy Bypass -File ~/.claude/skills/luz-skill-delete-cache/ensure-bash.ps1`

Then the bash examples below work from any shell.

```bash
# Auto-acquire token
ADMIN_TENANT_ID=00a04daf-f2b3-41d5-8c12-2d1b4c48a36a \
  ~/.claude/skills/luz-skill-delete-cache/delete_cache.sh \
  be01bf45-611a-4011-90a8-76227db1d190 CustomerIdAndEmaiMap

# Use a token you already have
TOKEN=eyJhbGciOi... \
  ~/.claude/skills/luz-skill-delete-cache/delete_cache.sh \
  be01bf45-611a-4011-90a8-76227db1d190 CustomerIdAndEmaiMap

# Different namespace
NAMESPACE=stg ADMIN_TENANT_ID=00a04daf-f2b3-41d5-8c12-2d1b4c48a36a \
  ~/.claude/skills/luz-skill-delete-cache/delete_cache.sh \
  be01bf45-611a-4011-90a8-76227db1d190 CustomerIdAndEmaiMap
```

## What the script does

1. Resolves `TENANT_ID` and `CACHE_KEY` (positional > env). Errors if missing.
2. Walks ports starting at `PORT` for up to `MAX_PORT_ATTEMPTS` candidates:
   - If `HOST:<candidate>` already accepts TCP, treats it as an existing port-forward and reuses it.
   - Otherwise launches `kubectl port-forward --address 0.0.0.0 services/api-forwarder <candidate>:<REMOTE_PORT> -n <NAMESPACE>` in a detached/minimized shell, captures kubectl's output to a per-port log, and waits up to 7 s.
   - On `bind: address already in use` / `unable to listen`, increments the candidate and retries.
3. If `TOKEN` is unset, calls the sibling `luz-skill-get-token` script with the resolved `PORT` and captures its stdout as the token.
4. Echoes the resolved tuple to stderr (tenant, cache key, namespace, port).
5. `DELETE http://HOST:<resolved-port>/luz_cache/api/{TENANT_ID}/{CACHE_KEY}` with `Authorization: <TOKEN_PREFIX><token>` (default prefix `Bearer `).
6. Prints `deleted` on `2xx`. Prints `not found` on `404`. On other status codes, prints `failed: HTTP <code>` along with any response body to stderr and exits non-zero.
