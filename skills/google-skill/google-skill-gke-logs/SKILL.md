---
name: google-skill-gke-logs
description: Read Google Cloud Logging entries for a Kubernetes container in a GKE cluster. Use when the user asks to "show logs for <X>", "tail logs", "fetch errors from <X>", or wants to inspect log output from a containerized workload running in GKE. Only CONTAINER is required — org defaults (klara-nonprod / dev / europe-west6) auto-fill cluster, namespace, and project. Bash-only; Windows users run via Git Bash or `bash` from PowerShell (one-time `ensure-bash.ps1` bootstrap).
---

# google-skill-gke-logs

Wraps `gcloud logging read` with a pre-built filter for `resource.type=k8s_container`, plus org defaults so the typical case is a single argument (the container name).

## Inputs

| Var | Required? | Default |
| --- | --- | --- |
| `CONTAINER`       | **yes** | (none — caller must specify; may be passed as 1st positional arg) |
| `NAMESPACE`       | optional | `dev` |
| `CLUSTER_NAME`    | optional | `klara-nonprod` |
| `CLUSTER_PROJECT` | optional | `klara-nonprod` |
| `LIMIT`           | optional | `2000` |
| `FRESHNESS`       | optional | `30m` (e.g. `1h`, `1d`) |
| `POD`             | optional | unset → all pods of the container |
| `SEVERITY`        | optional | unset → all severities (set to `ERROR` to keep ERROR and above, etc.) |
| `SEARCH`          | optional | unset → no text filter (set to e.g. `NullPointerException` to substring-match `textPayload`) |

The defaults match the klara setup. To inspect logs of a different container in a different namespace, override via env (`NAMESPACE=staging view_logs.sh some-container`).

## How to gather inputs

1. If the user passed args (e.g. `/google-skill-gke-logs CONTAINER=luz-docs SEVERITY=ERROR`), parse them as `KEY=VALUE` pairs. The container name may also arrive as a bare positional (e.g. `/google-skill-gke-logs luz-docs`).
2. **Always** ask for `CONTAINER` if missing — there is no safe default.
3. For everything else, do **not** prompt. Apply org defaults; the user can rerun with overrides if results aren't useful.
4. Print the resolved tuple before running so the user can sanity-check what's about to be queried.

## How to invoke

### Invocation (bash)

Path: `~/.claude/skills/google-skill-gke-logs/view_logs.sh`

Linux / macOS: run directly. Windows: run via Git Bash, or invoke from PowerShell as `bash ~/.claude/skills/google-skill-gke-logs/view_logs.sh ARGS`.

First-time Windows setup (only if `bash` is not on PATH yet):
`powershell -ExecutionPolicy Bypass -File ~/.claude/skills/google-skill-gke-logs/ensure-bash.ps1`

Then the bash examples below work from any shell.

```bash
# Common case
~/.claude/skills/google-skill-gke-logs/view_logs.sh luz-docs

# Errors only, last hour
SEVERITY=ERROR FRESHNESS=1h ~/.claude/skills/google-skill-gke-logs/view_logs.sh luz-docs

# Specific pod
POD=luz-docs-0 ~/.claude/skills/google-skill-gke-logs/view_logs.sh luz-docs
```

## What the script does

1. Resolves `CONTAINER` (positional arg > env var). Errors out if missing.
2. Applies org defaults for `NAMESPACE`, `CLUSTER_NAME`, `CLUSTER_PROJECT`, `LIMIT`, `FRESHNESS`.
3. Builds a Cloud Logging filter: `resource.type=k8s_container AND resource.labels.cluster_name=... AND resource.labels.namespace_name=... AND resource.labels.container_name=...`. Optionally appends `pod_name=`, `severity>=`, and `textPayload:` clauses.
4. Prints the resolved parameters and the filter being applied.
5. Runs `gcloud logging read "<FILTER>" --project=<CLUSTER_PROJECT> --limit=<LIMIT> --freshness=<FRESHNESS> --order=desc` (newest first).
