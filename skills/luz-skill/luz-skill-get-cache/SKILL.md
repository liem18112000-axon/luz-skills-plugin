---
name: luz-skill-get-cache
description: Fetch a Luz cache entry from the luz_cache service for a given tenant + cache key, via the api-forwarder in GKE. Use when the user asks to "get cache value for <key>", "show CustomerIdAndEmaiMap for tenant <id>", "fetch luz cache <key>", or any task that needs to inspect a cached value. Auto-starts a `kubectl port-forward` to `services/api-forwarder` on the chosen namespace if `localhost:PORT` is not already reachable, auto-increments the local port (8080 → 8081 → …) when the requested port is occupied, and auto-acquires an admin token when one is not supplied. Prints the cache body, or `not found` if the API returns 404 / null. Cross-platform — ships a Windows .cmd and a POSIX .sh runner.
---

# luz-skill-get-cache

Wraps `GET /luz_cache/api/{TENANT_ID}/{CACHE_KEY}`. The script:

1. Walks ports starting at `PORT` for up to `MAX_PORT_ATTEMPTS` candidates. If `localhost:<candidate>` is already up it reuses; otherwise it detaches `kubectl port-forward services/api-forwarder <candidate>:<REMOTE_PORT> -n NAMESPACE` into an isolated shell. If kubectl can't bind because the port is already taken by another process, it bumps to the next port and retries. The resolved port is used for all subsequent calls.
2. If `TOKEN` is not provided, acquires one via the sibling `luz-skill-get-token` skill (requires `ADMIN_TENANT_ID`). The resolved port is forwarded via env so the token skill reuses the same forward.
3. Issues the cache `GET` with `Authorization: Bearer <token>`.
4. Prints the response body. If status is `404` or the body is empty/`null`, prints `not found` instead.

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
2. **Always** ask for `TENANT_ID` and `CACHE_KEY` if missing.
3. If neither `TOKEN` nor `ADMIN_TENANT_ID` is provided, ask the user which one to use (you cannot auth without one).
4. Don't prompt for the rest — apply defaults.
5. Print the resolved tuple before running.

## How to invoke

### Windows (cmd / PowerShell)
Path: `%USERPROFILE%\.claude\skills\luz-skill-get-cache\get_cache.cmd`

```cmd
REM Auto-acquire token (needs ADMIN_TENANT_ID)
set ADMIN_TENANT_ID=00a04daf-f2b3-41d5-8c12-2d1b4c48a36a
"%USERPROFILE%\.claude\skills\luz-skill-get-cache\get_cache.cmd" be01bf45-611a-4011-90a8-76227db1d190 CustomerIdAndEmaiMap

REM Provide token directly
set TOKEN=eyJhbGciOi...
"%USERPROFILE%\.claude\skills\luz-skill-get-cache\get_cache.cmd" be01bf45-611a-4011-90a8-76227db1d190 CustomerIdAndEmaiMap

REM Different namespace
set NAMESPACE=stg
set ADMIN_TENANT_ID=00a04daf-f2b3-41d5-8c12-2d1b4c48a36a
"%USERPROFILE%\.claude\skills\luz-skill-get-cache\get_cache.cmd" be01bf45-611a-4011-90a8-76227db1d190 CustomerIdAndEmaiMap
```

### Linux / macOS (bash / zsh / Git Bash)
Path: `~/.claude/skills/luz-skill-get-cache/get_cache.sh`

```bash
# Auto-acquire token
ADMIN_TENANT_ID=00a04daf-f2b3-41d5-8c12-2d1b4c48a36a \
  ~/.claude/skills/luz-skill-get-cache/get_cache.sh \
  be01bf45-611a-4011-90a8-76227db1d190 CustomerIdAndEmaiMap

# Use a token you already have
TOKEN=eyJhbGciOi... \
  ~/.claude/skills/luz-skill-get-cache/get_cache.sh \
  be01bf45-611a-4011-90a8-76227db1d190 CustomerIdAndEmaiMap

# Different namespace
NAMESPACE=stg ADMIN_TENANT_ID=00a04daf-f2b3-41d5-8c12-2d1b4c48a36a \
  ~/.claude/skills/luz-skill-get-cache/get_cache.sh \
  be01bf45-611a-4011-90a8-76227db1d190 CustomerIdAndEmaiMap
```

## What the script does

1. Resolves `TENANT_ID` and `CACHE_KEY` (positional > env). Errors if missing.
2. Walks ports starting at `PORT` for up to `MAX_PORT_ATTEMPTS` candidates:
   - If `HOST:<candidate>` already accepts TCP, treats it as an existing port-forward and reuses it.
   - Otherwise launches `kubectl port-forward --address 0.0.0.0 services/api-forwarder <candidate>:<REMOTE_PORT> -n <NAMESPACE>` in a detached/minimized shell, captures kubectl's output to a per-port log, and waits up to 7 s.
   - On `bind: address already in use` / `unable to listen`, increments the candidate and retries.
3. If `TOKEN` is unset, calls the sibling `luz-skill-get-token` script with the resolved `PORT` (plus `NAMESPACE`, `REMOTE_PORT`, `HOST`, `BASIC_AUTH`, `ADMIN_TENANT_ID`) and captures its stdout as the token. The token skill sees the port as already up and reuses the same forward.
4. `GET http://HOST:<resolved-port>/luz_cache/api/{TENANT_ID}/{CACHE_KEY}` with `Authorization: <TOKEN_PREFIX><token>` (default prefix `Bearer `).
5. On HTTP 404 or empty/`null` body → prints `not found` and exits 0.
6. Otherwise prints the response body verbatim (pretty-printed if it parses as JSON).
