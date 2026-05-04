---
name: google-skill-cloudrun-logs
description: Read Google Cloud Logging entries for a Cloud Run service. Use when the user asks to "show logs for <service>", "tail Cloud Run logs", "fetch errors from <service>", or wants to inspect log output from a Cloud Run revision (e.g. dev-luz-thumbnail). Only SERVICE is required — org defaults (klara-nonprod / europe-west6) auto-fill project and region. Bash-only; Windows users run via Git Bash or `bash` from PowerShell (one-time `ensure-bash.ps1` bootstrap).
---

# google-skill-cloudrun-logs

Wraps `gcloud logging read` with a pre-built filter for `resource.type=cloud_run_revision`, plus org defaults so the typical case is a single argument (the Cloud Run service name).

## Inputs

| Var | Required? | Default |
| --- | --- | --- |
| `SERVICE`     | **yes** | (none — caller must specify; may be passed as 1st positional arg, e.g. `dev-luz-thumbnail`) |
| `PROJECT`     | optional | `klara-nonprod` |
| `REGION`      | optional | `europe-west6` |
| `LIMIT`       | optional | `2000` |
| `FRESHNESS`   | optional | `30m` (e.g. `1h`, `1d`) |
| `REVISION`    | optional | unset → all revisions of the service |
| `SEVERITY`    | optional | unset → all severities (set to `ERROR` to keep ERROR and above, etc.) |
| `SEARCH`      | optional | unset → no text filter (set to e.g. `OutOfMemory` to substring-match `textPayload`) |

The defaults match the klara setup (dev-* services live in `klara-nonprod`/`europe-west6`). Override via env (`PROJECT=klara-prod view_cloudrun_logs.sh prod-luz-thumbnail`).

## How to gather inputs

1. If the user passed args (e.g. `/google-skill-cloudrun-logs SERVICE=dev-luz-thumbnail SEVERITY=ERROR`), parse them as `KEY=VALUE` pairs. The service name may also arrive as a bare positional (e.g. `/google-skill-cloudrun-logs dev-luz-thumbnail`).
2. **Always** ask for `SERVICE` if missing — there is no safe default.
3. For everything else, do **not** prompt. Apply org defaults; the user can rerun with overrides if results aren't useful.
4. Print the resolved tuple before running so the user can sanity-check what's about to be queried.

## How to invoke

### Invocation (bash)

Path: `~/.claude/skills/google-skill-cloudrun-logs/view_cloudrun_logs.sh`

Linux / macOS: run directly. Windows: run via Git Bash, or invoke from PowerShell as `bash ~/.claude/skills/google-skill-cloudrun-logs/view_cloudrun_logs.sh ARGS`.

First-time Windows setup (only if `bash` is not on PATH yet):
`powershell -ExecutionPolicy Bypass -File ~/.claude/skills/google-skill-cloudrun-logs/ensure-bash.ps1`

Then the bash examples below work from any shell.

```bash
# Common case
~/.claude/skills/google-skill-cloudrun-logs/view_cloudrun_logs.sh dev-luz-thumbnail

# Errors only, last hour
SEVERITY=ERROR FRESHNESS=1h ~/.claude/skills/google-skill-cloudrun-logs/view_cloudrun_logs.sh dev-luz-thumbnail

# Different project / region
PROJECT=klara-prod REGION=us-central1 \
  ~/.claude/skills/google-skill-cloudrun-logs/view_cloudrun_logs.sh prod-luz-thumbnail
```

## What the script does

1. Resolves `SERVICE` (positional arg > env var). Errors out if missing.
2. Applies org defaults for `PROJECT`, `REGION`, `LIMIT`, `FRESHNESS`.
3. Builds a Cloud Logging filter: `resource.type=cloud_run_revision AND resource.labels.service_name=... AND resource.labels.location=...`. Optionally appends `revision_name=`, `severity>=`, and `textPayload:` clauses.
4. Prints the resolved parameters.
5. Runs `gcloud logging read "<FILTER>" --project=<PROJECT> --limit=<LIMIT> --freshness=<FRESHNESS> --order=desc` (newest first).

## Companion skill

For Kubernetes/GKE container logs (different `resource.type`), use `google-skill-gke-logs` instead. Same shape — single positional arg, org defaults.
