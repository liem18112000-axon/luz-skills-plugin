---
name: google-skill-gke-configmap
description: View and edit a Kubernetes ConfigMap currently in use by a workload in a GKE cluster, then restart the workload to pick up the change. Use when the user asks to "show the config", "what env is luz-docs using", "change DB_HOST in the config", "add this var", "remove that key from the configmap", etc. Defaults to NAMESPACE=dev. View-only is non-destructive; any add/change/remove is followed by a `kubectl rollout restart` of the affected StatefulSet/Deployment so the new values are loaded. Cross-platform — ships a Windows .cmd and a POSIX .sh viewer.
---

# google-skill-gke-configmap

Inspect or modify the live ConfigMap a GKE workload is using, then restart the workload to apply the change. Org defaults to `NAMESPACE=dev` and assumes `kubectl` is already pointed at the right cluster.

## Workflow (follow in order)

### Step 1 — Discover which ConfigMap to act on

If the user says "the luz-docs config" or names a workload rather than a ConfigMap, list the ConfigMaps that the workload mounts/imports. For a StatefulSet:

```bash
kubectl -n dev get statefulset luz-docs \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.envFrom[*].configMapRef.name}{"\n"}{end}'
```

For a Deployment, swap `statefulset` for `deployment`. Also check volume-mounted ConfigMaps:

```bash
kubectl -n dev get statefulset luz-docs \
  -o jsonpath='{.spec.template.spec.volumes[*].configMap.name}'
```

If multiple ConfigMaps are present, pick the most likely match by name (e.g. `luz-docs-env-configmap-...` for env-var requests) and confirm with the user before editing.

### Step 2 — View the ConfigMap

Use the viewer script:

```bash
~/.claude/skills/google-skill-gke-configmap/view_configmap.sh luz-docs-env-configmap-h7h69gmbt2
```

```cmd
"%USERPROFILE%\.claude\skills\google-skill-gke-configmap\view_configmap.cmd" luz-docs-env-configmap-h7h69gmbt2
```

Show the user the relevant portion of `data:` and confirm what they want to change before mutating.

### Step 3 — Mutate (only when user explicitly asks to add/change/remove)

Pick the right `kubectl patch`:

**Add or change a key** (strategic merge — overwrites if present):
```bash
kubectl -n dev patch configmap <NAME> --type=merge -p '{"data":{"KEY":"VALUE"}}'
```

For values containing special characters, prefer a heredoc with a JSON file or `--patch-file=` to avoid shell-quoting traps.

**Remove a key** (JSON patch — `op:remove`):
```bash
kubectl -n dev patch configmap <NAME> --type=json -p='[{"op":"remove","path":"/data/KEY"}]'
```

**Multiple changes in one shot**:
```bash
kubectl -n dev patch configmap <NAME> --type=json -p='[
  {"op":"add","path":"/data/NEW_KEY","value":"new"},
  {"op":"replace","path":"/data/OLD_KEY","value":"updated"},
  {"op":"remove","path":"/data/STALE_KEY"}
]'
```

After patching, re-run the viewer to confirm the change landed.

### Step 4 — Restart the workload to pick up the change

ConfigMap mounts (`volumeMounts`) update automatically over ~1 minute, but **`envFrom` does NOT** — env vars are baked into the pod spec at create time. If the workload uses `envFrom: configMapRef`, you must restart the pods.

```bash
kubectl -n dev rollout restart statefulset/<STS_NAME>
kubectl -n dev rollout status statefulset/<STS_NAME> --timeout=600s
```

Or invoke `google-skill-rollout-latest <sts>` — it short-circuits to `rollout restart` if the image is unchanged, which is exactly what we want here.

Confirm with the user before restarting; pod recreation is user-visible.

## Inputs (for the viewer script)

| Var | Required? | Default |
| --- | --- | --- |
| `CONFIGMAP` | **yes** | (none — caller must specify; may be passed as 1st positional arg) |
| `NAMESPACE` | optional | `dev` |
| `OUTPUT`    | optional | `yaml` (alternatives: `json`, `data` for just the `.data` map) |

## How to gather inputs

1. If the user names a workload (e.g. "luz-docs") rather than a ConfigMap, run Step 1 to discover ConfigMap names, then ask which one.
2. If they pass a ConfigMap directly, use it. The viewer is read-only — no confirmation needed.
3. For mutations, **always** echo back the proposed `kubectl patch` and the resulting expected `data:` change before running it.
4. For the rollout-restart step, **always** confirm — recreating pods is user-visible.

## Safety notes

- Mutating ConfigMaps in production-adjacent namespaces can break running workloads. Confirm the target namespace and ConfigMap name before patching.
- The `data:` field is a string-to-string map. If a value should be a number/bool, it must still be serialized as a string in the patch payload (`"PORT":"8080"`, not `"PORT":8080`).
- Some ConfigMaps are managed by a controller (Kustomize, Helm, ConfigConnector, External Secrets). Hand-patching such a ConfigMap will be reconciled away on the next sync. Look for owner references / labels like `app.kubernetes.io/managed-by` before assuming an in-place patch sticks.
