---
name: luz-skill-materialize-stats
description: Count documents by materialise state (`_hasUnrestrictedFolder` present/absent, restricted-with-codes, restricted-no-codes) for a Luz tenant in dev MongoDB. Use when the user wants to "check how many docs are materialised", "verify the backfill", "see materialise stats for tenant <id>", or "find out why per-folder counts return 0 after the materialise rollout". Port-forwards to `luz-mongodb02-cluster-rs-0:27017` in `dev-mongodb-clusters`, runs a Node + mongodb-driver script, prints a per-state breakdown with percentages plus a sample of restricted-with-codes docs. Bash-only; Windows users run via Git Bash or `bash` from PowerShell (one-time `ensure-bash.ps1` bootstrap). Mirrors the logic in `luz_docs/data/search-effective-security-class.js` but is parameterised on `TENANT_ID`.
---

# luz-skill-materialize-stats

Diagnostic for the LUZ-152936 materialise rollout. Connects to the dev MongoDB cluster as the tenant user and counts how many documents have the materialise sentinel fields populated:

| State | Filter | Meaning |
| --- | --- | --- |
| `total` | `{}` | All docs in the tenant |
| `materialised` | `{ _hasUnrestrictedFolder: { $exists: true } }` | Backfill / cascade has run on the doc |
| `unrestricted` | `{ _hasUnrestrictedFolder: true }` | Materialised AND eligible for the open branch of the security gate |
| `restrictedWithCodes` | `{ _hasUnrestrictedFolder: false, _effectiveFolderSecurityClassCodes: { $exists, $not size 0 } }` | Materialised AND restricted by inherited codes |
| `restrictedNoCodes` | `{ _hasUnrestrictedFolder: false, _effectiveFolderSecurityClassCodes: { $size: 0 } }` | Materialised AND no folder (or all empty) |
| `notMaterialised` | `{ _hasUnrestrictedFolder: { $exists: false } }` | Backfill never touched this doc |

If `notMaterialised` is non-zero while `MaterializeFacade.shouldUseMaterialized(...)` is returning `true`, those docs will be silently excluded by the security `$match` — explaining symptoms like "per-folder count is 0 for every folder" after the rollout.

## Inputs

| Var | Required? | Default |
| --- | --- | --- |
| `TENANT_ID`        | **yes** (1st positional or env) — e.g. `a5e06d74-137c-4a9e-9adc-9eccdccc2d17` |
| `MONGO_NAMESPACE`  | optional | `dev-mongodb-clusters` |
| `MONGO_POD`        | optional | `luz-mongodb02-cluster-rs-0` |
| `LOCAL_PORT`       | optional | `27017` (must be free) |
| `MONGO_PORT`       | optional | same as `LOCAL_PORT` |
| `SAMPLE_LIMIT`     | optional | `10` (sample of restricted-with-codes docs) |
| `LUZ_DOCS_REPO`    | optional | `$HOME/Kepler/luz_docs` (used to find `node_modules/mongodb`) |
| `KEEP_PORT_FORWARD`| optional | unset → tear down port-forward on exit; set `1` to leave it running |

## How to gather inputs

1. Parse `KEY=VALUE` args; tenant id may also arrive as a bare positional.
2. **Always** ask for `TENANT_ID` if missing — there is no safe default.
3. For everything else apply defaults; rerun with overrides if the tenant lives on a different shard or namespace.

## How to invoke

### Invocation (bash)

Path: `~/.claude/skills/luz-skill-materialize-stats/check_materialize.sh`

Linux / macOS: run directly. Windows: run via Git Bash, or invoke from PowerShell as `bash ~/.claude/skills/luz-skill-materialize-stats/check_materialize.sh ARGS`.

First-time Windows setup (only if `bash` is not on PATH yet):
`powershell -ExecutionPolicy Bypass -File ~/.claude/skills/luz-skill-materialize-stats/ensure-bash.ps1`

Then the bash examples below work from any shell.

```bash
# Common case
~/.claude/skills/luz-skill-materialize-stats/check_materialize.sh a5e06d74-137c-4a9e-9adc-9eccdccc2d17

# Different tenant on a non-default repo location
LUZ_DOCS_REPO=/work/luz_docs \
  ~/.claude/skills/luz-skill-materialize-stats/check_materialize.sh <TENANT_ID>

# Keep the port-forward running for follow-up queries
KEEP_PORT_FORWARD=1 ~/.claude/skills/luz-skill-materialize-stats/check_materialize.sh <TENANT_ID>
```

## What the script does

1. Resolves `TENANT_ID` (positional > env). Errors out if missing.
2. Probes `localhost:LOCAL_PORT` via `/dev/tcp`. If not reachable, runs `kubectl port-forward $MONGO_POD ${LOCAL_PORT}:27017 -n $MONGO_NAMESPACE` in the background.
3. Locates `node_modules/mongodb` under `$LUZ_DOCS_REPO/data` (fallback: `$LUZ_DOCS_REPO/node_modules`). Errors out with a clear message if neither exists.
4. Runs `node check_materialize.js` with `NODE_PATH` set so the bundled JS can `require('mongodb')`.
5. The JS connects with the tenant credentials (`mongodb://<tenant>:<tenant>@host:port/<tenant>`), runs `countDocuments` for each state, prints a percentage breakdown, and shows up to `SAMPLE_LIMIT` restricted-with-codes docs.
6. On exit, tears down the port-forward unless `KEEP_PORT_FORWARD=1`.

## Caveats

- **Local port 27017 must be free.** The MongoDB driver URI hard-codes the port; if you need a different local port, set `LOCAL_PORT=<n>` AND `MONGO_PORT=<n>` so the driver connects to the same place.
- **Tenant credentials.** The connection uses `tenantId:tenantId` as user/password — the standard luz-jsonstore pattern. If a tenant uses a different mongodb auth scheme this will fail.
- **Read-only.** The script only runs `countDocuments` and a small `find().limit(SAMPLE_LIMIT)`. It will not mutate any data.
- **Mongo dependency.** Reuses `mongodb` from `luz_docs/data/node_modules` to avoid bundling a second copy. If you remove `data/node_modules`, the skill errors out.
