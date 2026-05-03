---
name: luz-skill-get-token
description: Acquire an all-tenant access token from the Luz Security service via the api-forwarder in GKE. Use when the user asks to "get a luz token", "fetch an admin token", or any task that needs a Luz bearer token. Auto-starts a `kubectl port-forward` to `services/api-forwarder` on the chosen namespace if `localhost:PORT` is not already reachable, and auto-increments the local port (8080 → 8081 → …) when the requested port is occupied by another process. Cross-platform — ships a Windows .cmd and a POSIX .sh runner.
---

# luz-skill-get-token

Wraps the `POST /luzsec/api/{ADMIN_TENANT_ID}/access/tokens?type=all-tenant` call. If the API forwarder is not reachable on `localhost:PORT`, the script detaches a `kubectl port-forward services/api-forwarder LOCAL:REMOTE_PORT -n NAMESPACE` into an isolated shell, waits up to 7 s, then issues the token request. If the chosen local port is occupied, the script bumps to `PORT+1`, `PORT+2`, …, up to `MAX_PORT_ATTEMPTS` total attempts, and uses whichever port succeeded for the actual API call.

The token value (the `token` field of the JSON response) is printed on stdout — nothing else — so callers can capture it via command substitution. The resolved local port is logged to stderr.

## Inputs

| Var | Required? | Default |
| --- | --- | --- |
| `ADMIN_TENANT_ID`   | **yes** | (none — pass as 1st positional arg, e.g. `00a04daf-f2b3-41d5-8c12-2d1b4c48a36a`) |
| `NAMESPACE`         | optional | `dev` |
| `PORT`              | optional | `8080` (starting local port — auto-increments if busy) |
| `REMOTE_PORT`       | optional | `8080` (api-forwarder service port — never increments) |
| `MAX_PORT_ATTEMPTS` | optional | `10` (max consecutive ports to try before giving up) |
| `HOST`              | optional | `localhost` |
| `BASIC_AUTH`        | optional | `YWRtaW46YWRtaW4=` (base64 of `admin:admin`) |

## How to gather inputs

1. Parse `KEY=VALUE` args, or accept a bare positional UUID for `ADMIN_TENANT_ID`.
2. **Always** ask for `ADMIN_TENANT_ID` if missing.
3. Don't prompt for the rest — apply defaults.
4. Print the resolved tuple before running.

## How to invoke

### Windows (cmd / PowerShell)
Path: `%USERPROFILE%\.claude\skills\luz-skill-get-token\get_token.cmd`

```cmd
"%USERPROFILE%\.claude\skills\luz-skill-get-token\get_token.cmd" 00a04daf-f2b3-41d5-8c12-2d1b4c48a36a

REM Different namespace
set NAMESPACE=stg
"%USERPROFILE%\.claude\skills\luz-skill-get-token\get_token.cmd" 00a04daf-f2b3-41d5-8c12-2d1b4c48a36a
```

### Linux / macOS (bash / zsh / Git Bash)
Path: `~/.claude/skills/luz-skill-get-token/get_token.sh`

```bash
~/.claude/skills/luz-skill-get-token/get_token.sh 00a04daf-f2b3-41d5-8c12-2d1b4c48a36a

# Capture the token
TOKEN=$(~/.claude/skills/luz-skill-get-token/get_token.sh 00a04daf-f2b3-41d5-8c12-2d1b4c48a36a)

# Different namespace
NAMESPACE=stg ~/.claude/skills/luz-skill-get-token/get_token.sh 00a04daf-f2b3-41d5-8c12-2d1b4c48a36a
```

## What the script does

1. Resolves `ADMIN_TENANT_ID` (positional > env). Errors if missing.
2. Walks ports starting at `PORT` for up to `MAX_PORT_ATTEMPTS` candidates:
   - If `localhost:<candidate>` already accepts TCP, treats it as an existing port-forward and reuses it.
   - Otherwise launches `kubectl port-forward --address 0.0.0.0 services/api-forwarder <candidate>:<REMOTE_PORT> -n <NAMESPACE>` in a detached/minimized shell, captures kubectl's output to a per-port log, and waits up to 7 s for the port to come up.
   - If kubectl exits with a `bind: address already in use` / `unable to listen` error, increments the candidate and retries.
3. `POST http://HOST:<resolved-port>/luzsec/api/{ADMIN_TENANT_ID}/access/tokens?type=all-tenant` with `Authorization: Basic {BASIC_AUTH}`.
4. Extracts the `token` field from the JSON body and prints it on stdout. Status messages (including the resolved port) go to stderr.
5. Leaves the port-forward running so subsequent calls (e.g. luz-skill-get-cache) can reuse it on the same port.
