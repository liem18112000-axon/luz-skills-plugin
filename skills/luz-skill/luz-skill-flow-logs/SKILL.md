---
name: luz-skill-flow-logs
description: Read interleaved Cloud Logging entries across the 4 Luz services along the request flow (luz-webclient → luz-docs-view-controller → luz-docs → luz-jsonstore). Use when the user wants to "trace a request", "correlate errors across services", or "see the flow logs for tenant <id>". A single multi-container `gcloud logging read` so entries from all four services come back chronologically interleaved. Multi-service counterpart of `google-skill-gke-logs`. Bash-only; Windows users run via Git Bash or `bash` from PowerShell (one-time `ensure-bash.ps1` bootstrap).
---

# luz-skill-flow-logs

Read interleaved Cloud Logging entries across the four services in the Luz request flow:

```
luz-webclient → luz-docs-view-controller → luz-docs → luz-jsonstore
```

A single `gcloud logging read` call with a multi-container OR filter so entries from all four services come back in chronological order — useful for tracing a single request through the chain or correlating errors.

This is the multi-service counterpart of `google-skill-gke-logs` (which reads one container). Reuse that skill when you only need one service; reach for this one when correlating across the chain.

## Inputs

| Var | Required? | Default |
| --- | --- | --- |
| `SEARCH`           | strongly recommended (env or 1st positional arg) — substring match on `textPayload`, usually a tenant id or request id |
| `NAMESPACE`        | optional | `dev` |
| `CLUSTER_NAME`     | optional | `klara-nonprod` |
| `CLUSTER_PROJECT`  | optional | `klara-nonprod` |
| `LIMIT`            | optional | `5000` (split across 4 services) |
| `FRESHNESS`        | optional | `30m` (e.g. `1h`, `1d`) |
| `SEVERITY`         | optional | unset → all severities (set `ERROR` to keep ERROR and above) |
| `SERVICES`         | optional | `luz-webclient,luz-docs-view-controller,luz-docs,luz-jsonstore` — override to scope down (e.g. `luz-docs,luz-jsonstore`) |

`SEARCH` is not strictly required by the script, but without it the result is unfiltered noise across all four services. Always pass a tenant id, request id, or other narrowing substring.

## How to gather inputs

1. If the user passed args (e.g. `/luz-skill-flow-logs SEARCH=a5e06d74-... SEVERITY=ERROR`), parse them as `KEY=VALUE` pairs. The search term may also arrive as a bare positional (e.g. `/luz-skill-flow-logs a5e06d74-137c-4a9e-9adc-9eccdccc2d17`).
2. **Recommend** asking for `SEARCH` if missing — without it the output is too broad to analyse.
3. For everything else, do **not** prompt; apply org defaults. Tell the user the resolved tuple before running so they can sanity-check.

## How to invoke

### Invocation (bash)

Path: `~/.claude/skills/luz-skill-flow-logs/trace_flow_logs.sh`

Linux / macOS: run directly. Windows: run via Git Bash, or invoke from PowerShell as `bash ~/.claude/skills/luz-skill-flow-logs/trace_flow_logs.sh ARGS`.

First-time Windows setup (only if `bash` is not on PATH yet):
`powershell -ExecutionPolicy Bypass -File ~/.claude/skills/luz-skill-flow-logs/ensure-bash.ps1`

Then the bash examples below work from any shell.

```bash
# Common case (search by tenant id, last 30m)
~/.claude/skills/luz-skill-flow-logs/trace_flow_logs.sh a5e06d74-137c-4a9e-9adc-9eccdccc2d17

# Errors only, last hour, more entries
SEVERITY=ERROR FRESHNESS=1h LIMIT=10000 \
  ~/.claude/skills/luz-skill-flow-logs/trace_flow_logs.sh a5e06d74-137c-4a9e-9adc-9eccdccc2d17

# Scope to just the inner two services (skip web/view-controller chatter)
SERVICES=luz-docs,luz-jsonstore \
  ~/.claude/skills/luz-skill-flow-logs/trace_flow_logs.sh a5e06d74-137c-4a9e-9adc-9eccdccc2d17
```

## What the script does

1. Resolves `SEARCH` (positional arg > env var). Empty SEARCH is permitted but discouraged.
2. Applies org defaults for `NAMESPACE`, `CLUSTER_NAME`, `CLUSTER_PROJECT`, `LIMIT`, `FRESHNESS`, and `SERVICES`.
3. Splits `SERVICES` on commas and builds an OR clause:
   `(resource.labels.container_name=svc1 OR resource.labels.container_name=svc2 …)`.
4. Builds the full Cloud Logging filter with `resource.type=k8s_container`, cluster, namespace, the container OR clause, and optional `severity>=` / `textPayload:` clauses.
5. Prints the resolved parameters and the filter being applied.
6. Runs `gcloud logging read "<FILTER>" --project=<CLUSTER_PROJECT> --limit=<LIMIT> --freshness=<FRESHNESS> --order=desc` (newest first; entries from all selected services interleaved by timestamp).

## How to analyse the output

After fetching, look for:

- **Request boundaries** — `io.undertow.accesslog` lines on `luz-webclient` / `luz-docs-view-controller` / `luz-docs` mark the entry/exit of each hop. Match by approximate timestamp + tenant id to follow a request through the chain.
- **Errors at each hop** — `severity>=WARNING` plus the `[ch.klara…]` package on the offending service tells you which hop failed.
- **Mongo-side issues** — `luz-jsonstore` `SEVERE` lines surface aggregate / sort errors (e.g. error 292 `QueryExceededMemoryLimitNoDiskUseAllowed`). Cross-reference back to the luz-docs request body that triggered it (logged by `JsonStoreLoggingFilter`).
- **Slow hops** — `time-consuming=` on access log lines tells you which service is the bottleneck for a given request.

If results look truncated, raise `LIMIT` or narrow `FRESHNESS`. If output is too noisy, narrow `SERVICES` to the inner pair you care about.
