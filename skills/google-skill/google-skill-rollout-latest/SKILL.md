---
name: google-skill-rollout-latest
description: Roll a Kubernetes StatefulSet to the most recently uploaded image tag in Google Artifact Registry. Use when the user asks to "deploy latest", "rollout latest", "sync StatefulSet to GAR", or "update <sts> to the newest image". Only STATEFULSET is required — org defaults (klara-repo / klara-nonprod / dev / europe-west6) auto-fill the rest, and CONTAINER + ARTIFACT_IMAGE default to the STATEFULSET name. If the StatefulSet is already at the latest tag, the script does a `kubectl rollout restart` instead of mutating the spec. Otherwise it updates both the live container spec and the kubectl.kubernetes.io/last-applied-configuration annotation so future kubectl apply runs do not compute a bogus diff. Bash-only; Windows users run via Git Bash or `bash` from PowerShell (one-time `ensure-bash.ps1` bootstrap).
---

# google-skill-rollout-latest

Rolls a Kubernetes StatefulSet container to the latest tag in a Google Artifact Registry repo. Cross-platform (Windows + Linux/macOS). Surgical updates only — never replaces the full StatefulSet yaml.

## Behaviour

After resolving the latest tag from Artifact Registry the script reads the current container image off the StatefulSet and branches:

- **Already at latest tag** → `kubectl rollout restart statefulset/<sts>`. No spec mutation, no annotation rewrite. Useful when you want to recycle pods to pick up env/ConfigMap changes or just re-pull.
- **Different tag** → `kubectl set image ...`, then patches the `kubectl.kubernetes.io/last-applied-configuration` annotation in place so future `kubectl apply` runs don't see a stale baseline.

Either way, the script ends with `kubectl rollout status ... --timeout=600s` so you can tell when the rollout is done.

## Inputs

| Var | Required? | Default |
| --- | --- | --- |
| `STATEFULSET`      | **yes** | (none — caller must specify; may be passed as 1st positional arg) |
| `NAMESPACE`        | optional | `dev` |
| `CONTAINER`        | optional | same as `STATEFULSET` |
| `ARTIFACT_IMAGE`   | optional | same as `STATEFULSET` |
| `ARTIFACT_PROJECT` | optional | `klara-repo` |
| `ARTIFACT_REGION`  | optional | `europe-west6` |
| `ARTIFACT_REPO`    | optional | `artifact-registry-container-images` |
| `CLUSTER_PROJECT`  | optional | `klara-nonprod` |
| `CLUSTER_NAME`     | optional | `klara-nonprod` (only used by the commented `gcloud get-credentials` line) |
| `CLUSTER_ZONE`     | optional | `europe-west6-a` (same) |

The defaults match the klara setup. To roll a different StatefulSet to the same cluster, only `STATEFULSET=<name>` is needed. To target a different env, pass `NAMESPACE=staging` (or whatever). Every var is overridable.

`CLUSTER_NAME` and `CLUSTER_ZONE` are only consumed by the commented-out `gcloud container clusters get-credentials` line. The script does NOT auto-refresh kubeconfig — it assumes `kubectl` is already pointed at the right cluster.

## How to gather inputs

1. If the user passed args (e.g. `/google-skill-rollout-latest STATEFULSET=foo NAMESPACE=staging`), parse them as `KEY=VALUE` pairs. The trigger name may also arrive as a bare positional (e.g. `/google-skill-rollout-latest luz-docs`).
2. **Always** ask for `STATEFULSET` if missing — there is no safe default.
3. For everything else, do **not** prompt — let the org defaults apply. The script prints the resolved tuple before running so the user can sanity-check.
4. Confirm the resolved tuple back to the user before running — this mutates a live cluster.

## How to invoke

### Invocation (bash)

Path: `~/.claude/skills/google-skill-rollout-latest/rollout_latest.sh`

Linux / macOS: run directly. Windows: run via Git Bash, or invoke from PowerShell as `bash ~/.claude/skills/google-skill-rollout-latest/rollout_latest.sh ARGS`.

First-time Windows setup (only if `bash` is not on PATH yet):
`powershell -ExecutionPolicy Bypass -File ~/.claude/skills/google-skill-rollout-latest/ensure-bash.ps1`

Then the bash examples below work from any shell.

```bash
# Common case
~/.claude/skills/google-skill-rollout-latest/rollout_latest.sh luz-docs

# Override defaults
NAMESPACE=staging ~/.claude/skills/google-skill-rollout-latest/rollout_latest.sh luz-docs

# Different image name than statefulset
ARTIFACT_IMAGE=other-image CONTAINER=other-container \
  ~/.claude/skills/google-skill-rollout-latest/rollout_latest.sh luz-docs
```

Requires `gcloud`, `kubectl`, and `sed` on PATH. The `.sh` runner uses `set -euo pipefail` and prints the resolved parameter set before mutating anything.

## What the script does (5 steps)

1. **Resolve latest tag** via `gcloud artifacts docker images list <IMAGE_PATH> --include-tags --sort-by=~UPDATE_TIME --limit=1 --format="value(tags)"`. Whitespace is trimmed.
2. **Print current image** on the StatefulSet for an audit trail.
3. **Patch spec** with `kubectl set image statefulset/<sts> <container>=<image>:<tag>`.
4. **Sync `kubectl.kubernetes.io/last-applied-configuration` annotation** — reads it, regex-replaces only `/<ARTIFACT_IMAGE>:<oldtag>` inside the JSON blob, writes it back via `kubectl annotate --overwrite`. Other images in the annotation (e.g. `nginx-metrics-proxy:latest`) are untouched. Skipped cleanly if the annotation is absent or already in sync.
5. **Wait for rollout** with `kubectl rollout status ... --timeout=600s`.

## Safety notes

- This is a destructive, cluster-mutating action. Always confirm the resolved parameters with the user before running.
- If `kubectl` is pointing at the wrong context, the patch lands in the wrong cluster. Consider running `kubectl config current-context` first when unsure.
- `gcloud auth login` and cluster credentials must already be valid; the script does not authenticate.