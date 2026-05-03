---
name: google-skill-trigger-cloud-build
description: Run a Google Cloud Build trigger by name. Use when the user asks to "trigger build", "kick off Cloud Build", "rebuild image", or "run the <X> trigger on branch <Y>". Only TRIGGER_NAME is required — org defaults (klara-infra / europe-west6) auto-fill project and region, BRANCH defaults to the current git branch, and the skill short-circuits if the local HEAD SHA already exists as the latest tag in Artifact Registry. Cross-platform — ships a Windows .cmd and a POSIX .sh runner.
---

# google-skill-trigger-cloud-build

Wraps `gcloud builds triggers run <name> --project=... --region=... --branch=...` with org defaults baked in, branch inferred from the local git checkout, and a "code already built" short-circuit that consults Artifact Registry. Typical case is a single argument.

## Inputs

| Var | Required? | Default |
| --- | --- | --- |
| `TRIGGER_NAME`     | **yes**  | (none — caller must specify; may be passed as 1st positional arg) |
| `BUILD_PROJECT`    | optional | `klara-infra` |
| `REGION`           | optional | `europe-west6` |
| `BRANCH`           | optional | current git branch (`git rev-parse --abbrev-ref HEAD`). Errors if not inside a git work tree or if HEAD is detached. |
| `ARTIFACT_PROJECT` | optional | `klara-repo` |
| `ARTIFACT_REGION`  | optional | `europe-west6` |
| `ARTIFACT_REPO`    | optional | `artifact-registry-container-images` |
| `ARTIFACT_IMAGE`   | optional | same as `TRIGGER_NAME` |
| `FORCE`            | optional | unset. Set to `1` to skip the "already-built" short-circuit and always run the trigger. |

The `ARTIFACT_*` vars are only used for the "already-built" check; they have no effect on which trigger runs or which build config is used.

## "Already-built" short-circuit

Before running the trigger, the script:
1. Reads `git rev-parse HEAD` (full local commit SHA).
2. Reads the most-recently-pushed tag in `${ARTIFACT_REGION}-docker.pkg.dev/${ARTIFACT_PROJECT}/${ARTIFACT_REPO}/${ARTIFACT_IMAGE}` via `gcloud artifacts docker images list ... --sort-by=~UPDATE_TIME --limit=1`.
3. If they match (case-insensitive), prints `Code is already in latest build.` and exits 0 **without** kicking off a build.
4. Set `FORCE=1` to skip this check. The check is also skipped if the working directory is not a git repo.

This avoids burning Cloud Build minutes when the latest pushed image already corresponds to the local HEAD.

## How to gather inputs

1. If the user passed args (e.g. `/google-skill-trigger-cloud-build TRIGGER_NAME=luz-docs BRANCH=master`), parse them as `KEY=VALUE` pairs. The trigger name may also arrive as a bare positional (e.g. `/google-skill-trigger-cloud-build luz-docs`).
2. **Always** ask for `TRIGGER_NAME` if missing — there is no safe default.
3. For everything else, do **not** prompt — let the org defaults / git lookup / AR check apply. If git is unavailable or HEAD is detached the script will exit with a clear error and the user can rerun with `BRANCH=` set.
4. Confirm the resolved tuple back to the user before running — this kicks off a real Cloud Build run.

## How to invoke

### Windows (cmd / PowerShell)
Path: `%USERPROFILE%\.claude\skills\google-skill-trigger-cloud-build\trigger_build.cmd`

Common case (project / region / branch all default):
```cmd
"%USERPROFILE%\.claude\skills\google-skill-trigger-cloud-build\trigger_build.cmd" luz-docs
```

Override anything via env first:
```cmd
set BRANCH=master
"%USERPROFILE%\.claude\skills\google-skill-trigger-cloud-build\trigger_build.cmd" luz-docs
```

### Linux / macOS (bash / zsh)
Path: `~/.claude/skills/google-skill-trigger-cloud-build/trigger_build.sh`

```bash
# Common case
~/.claude/skills/google-skill-trigger-cloud-build/trigger_build.sh luz-docs

# Override branch / project / region
BRANCH=master ~/.claude/skills/google-skill-trigger-cloud-build/trigger_build.sh luz-docs
BUILD_PROJECT=other-infra REGION=us-central1 \
  ~/.claude/skills/google-skill-trigger-cloud-build/trigger_build.sh some-trigger
```

## What the script does

1. Resolves `TRIGGER_NAME` (positional arg > env var). Errors out if missing.
2. Applies org defaults for `BUILD_PROJECT`, `REGION`, and the four `ARTIFACT_*` vars.
3. Resolves `BRANCH`: env var > `git rev-parse --abbrev-ref HEAD`. Errors out if not inside a git work tree or if HEAD is detached.
4. Unless `FORCE=1`, compares `git rev-parse HEAD` against the latest tag in Artifact Registry (`${IMAGE_PATH}`). If equal → prints "Code is already in latest build." and exits 0.
5. Prints the resolved 4-tuple, then runs `gcloud builds triggers run <name> --project=... --region=... --branch=...`.

## Safety notes

- This launches a real Cloud Build run that consumes minutes and may push a new image tag. Confirm the resolved parameters before running.
- The auto-discovered branch is whatever the trigger config says — if the trigger uses a branch *regex*, the stripped result may not be a valid ref name. If the run command rejects it, pass `BRANCH` explicitly.
- The script does not authenticate; `gcloud` and the active account must already have `cloudbuild.builds.create` (or equivalent) on the project.
