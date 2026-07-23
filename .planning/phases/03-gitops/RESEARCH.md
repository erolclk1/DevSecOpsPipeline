# Phase 3: GitOps — Research

**Researched:** 2026-07-23
**Domain:** ArgoCD v3.4.4 + Kyverno v1.18.2 on k3s single-node (Rancher Desktop WSL2)
**Confidence:** MEDIUM-HIGH — commands from official docs, chart values from raw YAML sources; SSA defaults and Kyverno/ArgoCD flap behavior carry MEDIUM confidence due to version-specific gaps

---

## Project Constraints (from CLAUDE.md)

| Constraint | Detail |
|------------|--------|
| Registry hostname | `host.rancher-desktop.internal:5001` in all manifests and ArgoCD Application CR |
| Registry push | Always `localhost:5001` from Windows host (docker push), never `host.rancher-desktop.internal:5001` from host |
| Port | 5001 (5000 conflicts with Rancher Desktop's internal proxy) |
| Insecure registry | Configured via `cluster/insecure-registry.start` provisioning script (daemon.json) — `registries.yaml` alone is NOT sufficient for dockerd engine |
| Jenkins MUST NOT kubectl | Jenkins commits to `deploy/overlays/local/` only; ArgoCD syncs to cluster — never `kubectl apply` from Jenkins |
| Falco driver | `driver.kind=modern_ebpf` — not `auto` |
| Image tags | Always git short SHA, never `:latest` — enforced by Kyverno `disallow-latest-tag` |
| ArgoCD version | v3.4.4 via Helm chart `argo/argo-cd 10.1.0` |
| Kyverno | latest stable (v1.18.2 / chart 3.8.2 as of 2026-07-23) |

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GITOPS-01 | ArgoCD v3.4.4 installed via Helm chart 10.1.0 in `argocd` namespace | Q1: exact helm command |
| GITOPS-02 | ArgoCD Application CR watches `deploy/overlays/local/` with auto-sync, self-heal, prune enabled | Q2: full Application YAML |
| GITOPS-03 | Kustomize overlay uses image patch — CI manifest bump is one YAML line change | Already implemented in Phase 2; verify ArgoCD detects it |
| GITOPS-04 | Kyverno with 4 policies: disallow-latest-tag, restrict-image-registries, disallow-privileged-containers, require-resource-limits | Q4+Q5: exact install + policy YAMLs |
| GITOPS-05 | ArgoCD self-heal: manual kubectl edit reverted within sync interval | Q3: self-heal demonstration procedure |
| GITOPS-06 | Kyverno PolicyReport CR shows admission decisions during demo | Q6: PolicyReport query commands |
</phase_requirements>

---

## Summary

Phase 3 installs two cluster add-ons (ArgoCD + Kyverno) and wires a Git-native deploy path for the already-deployed demoapp. The app is already running via raw `kubectl apply` (Phase 2 outcome) — Phase 3 transfers ownership to ArgoCD without changing the app itself.

The main implementation risks are: (a) the ArgoCD/Kyverno sync loop caused by Kyverno mutation annotations causing continuous `Synced→OutOfSync` flapping, and (b) Kyverno admission webhook blocking legitimate system pods during install if configured with `Enforce` mode prematurely.

**Primary recommendation:** Install ArgoCD first and verify sync, then install Kyverno with all 4 policies in `Audit` mode, then switch `validationFailureAction: Enforce` only for `disallow-latest-tag` (the demo-critical policy) after verifying the demoapp pod passes that policy with its SHA-tagged image.

---

## Q1: ArgoCD v3.4.4 Helm Install

### Helm Repository Setup

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

### Verify chart version maps to ArgoCD v3.4.4

Chart `argo-cd 10.1.0` deploys `appVersion: v3.4.4` (confirmed from `Chart.yaml`). [HIGH confidence]

### Install Command (non-HA, single-node)

```bash
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version 10.1.0 \
  --set redis-ha.enabled=false \
  --set controller.replicas=1 \
  --set server.replicas=1 \
  --set repoServer.replicas=1 \
  --set applicationSet.replicas=1 \
  --set dex.enabled=false \
  --set server.resources.limits.memory=256Mi \
  --set server.resources.limits.cpu=500m \
  --set server.resources.requests.memory=128Mi \
  --set server.resources.requests.cpu=50m \
  --set controller.resources.limits.memory=512Mi \
  --set controller.resources.limits.cpu=500m \
  --set controller.resources.requests.memory=256Mi \
  --set controller.resources.requests.cpu=100m \
  --set repoServer.resources.limits.memory=512Mi \
  --set repoServer.resources.limits.cpu=500m \
  --set repoServer.resources.requests.memory=128Mi \
  --set repoServer.resources.requests.cpu=50m \
  --set redis.resources.limits.memory=128Mi \
  --set redis.resources.requests.memory=64Mi \
  --wait
```

**Key flags explained:**
- `redis-ha.enabled=false` — uses single-node Redis (not the Redis HA subchart with 3 replicas + HAProxy). **This is the single most important RAM-saving flag.** Redis HA adds ~500MB RAM.
- `dex.enabled=false` — disables the OIDC provider (not needed for thesis; saves ~100MB RAM)
- `controller.replicas=1` — default, but explicit for clarity
- `applicationSet.replicas=1` — one ApplicationSet controller is sufficient

**RAM budget estimate for ArgoCD on 6GB VM:**
| Component | Memory limit set |
|-----------|-----------------|
| argocd-server | 256Mi |
| argocd-repo-server | 512Mi |
| argocd-application-controller | 512Mi |
| argocd-redis | 128Mi |
| **Total** | **~1.4 GB** (leaves headroom for k3s + demoapp + Kyverno) |

**Confidence:** HIGH for chart version / non-HA flags. MEDIUM for exact resource limits (these are conservative estimates — adjust up if OOMKilled).

### Verify ArgoCD is Running

```bash
kubectl get pods -n argocd
# Expected: all pods Running, Ready
kubectl rollout status deployment/argocd-server -n argocd
```

---

## Q2: ArgoCD Application CR

**File to create:** `bootstrap/argocd/application.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demoapp
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/<YOUR_ORG>/<YOUR_REPO>.git
    targetRevision: main
    path: deploy/overlays/local
    kustomize: {}
  destination:
    server: https://kubernetes.default.svc
    namespace: demoapp
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
      - RespectIgnoreDifferences=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  ignoreDifferences:
    - group: apps
      kind: Deployment
      managedFieldsManagers:
        - kyverno
        - kyverno-background-controller
        - kube-controller-manager
```

**Notes:**
- `repoURL` must be substituted with the actual GitHub repo URL (not a local path — ArgoCD controller runs inside the k3s VM and cannot reach macOS filesystem paths)
- `kustomize: {}` — empty map is sufficient; ArgoCD auto-detects `kustomization.yaml` in the path and invokes the bundled kustomize
- `CreateNamespace=false` — the `demoapp` namespace already exists (created in Phase 2 base manifests)
- `RespectIgnoreDifferences=true` — required for `ignoreDifferences` to take effect during sync (not just during diff). Without this, ArgoCD still applies the desired state even for ignored fields.
- `finalizers` — adds cascade delete behavior: when the Application CR is deleted, ArgoCD also prunes the cluster resources. Correct for thesis; remove if you want to delete Application without destroying workloads.

**Applying the Application:**
```bash
kubectl apply -f bootstrap/argocd/application.yaml
```

**Watching initial sync:**
```bash
kubectl get application demoapp -n argocd -w
# Should transition: OutOfSync (or Unknown) → Synced, then Healthy
```

**Confidence:** HIGH for CR structure (from official declarative-setup docs). MEDIUM for `ignoreDifferences` field names (Kyverno manager names `kyverno` and `kyverno-background-controller` are inferred from component names — verify empirically during execution).

---

## Q3: ArgoCD Sync Loop Risk and ignoreDifferences

### Does ArgoCD v3.4 enable Server-Side Apply by default?

**Answer: No.** Server-Side Apply is opt-in per-application or per-resource. It must be explicitly set via:
```yaml
syncOptions:
  - ServerSideApply=true
```

The v3.3→v3.4 upgrade guide confirms SSA is **not a new default** — it is only required for upgrading the ArgoCD installation itself via the Helm chart (to handle the oversized ApplicationSet CRD). Normal application syncs continue to use client-side apply unless opted in. [HIGH confidence — verified from upgrade guide]

**Do NOT add `ServerSideApply=true` to the demoapp Application.** It adds complexity without benefit for this simple use case and can interact unexpectedly with Kyverno's field management.

### How Kyverno Causes Sync Loops

Kyverno's mutating webhooks add or modify fields on resources:
1. **`kyverno.io/` annotations** on resources (policy hash, mutation tracking)
2. **Managed fields entries** — Kyverno claims ownership of fields it mutated via server-side-apply field tracking
3. **Pod spec mutations** — e.g., if a mutating policy injects sidecars, security context defaults, etc.

ArgoCD compares live cluster state to Git desired state. If Kyverno added a field that is not in Git, ArgoCD sees `OutOfSync` and re-applies. Kyverno re-mutates. Repeat.

**The fix: `ignoreDifferences` with `managedFieldsManagers`**

```yaml
ignoreDifferences:
  - group: apps
    kind: Deployment
    managedFieldsManagers:
      - kyverno
      - kyverno-background-controller
      - kube-controller-manager
```

This tells ArgoCD: "For Deployment resources, ignore any field differences where the last manager was `kyverno` or `kyverno-background-controller`."

Combined with `syncOptions: [RespectIgnoreDifferences=true]`, ArgoCD will not continuously re-apply resources that only differ in Kyverno-managed fields.

**Additional `ignoreDifferences` if still flapping:**

If specific annotations cause flapping, add jsonPointer exclusions:
```yaml
ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
      - /metadata/annotations/policies.kyverno.io~1last-applied-patches
      - /metadata/annotations/kyverno.io~1patches
    managedFieldsManagers:
      - kyverno
      - kyverno-background-controller
      - kube-controller-manager
```

**Note on `~1`:** In JSON Pointer syntax (RFC 6901), `/` in a key is encoded as `~1`. So `policies.kyverno.io/last-applied-patches` becomes `policies.kyverno.io~1last-applied-patches`.

**Open question to resolve empirically:** The 4 policies installed in Phase 3 are **validate-only** policies (no mutating rules). If no Kyverno mutating policies are installed, the sync loop may not occur at all for this thesis setup. Monitor ArgoCD status after install; add `ignoreDifferences` only if OutOfSync appears after first Synced state.

**Confidence:** MEDIUM — mechanism is well-understood; exact annotation key names require empirical verification on this specific Kyverno version and chart combination.

---

## Q4: Kyverno Helm Install

### Version Confirmed
- **Kyverno app version:** v1.18.2 (latest stable as of 2026-07-23)
- **Helm chart version:** 3.8.2 (verified from kyverno.github.io/kyverno/index.yaml)

### Helm Install Command (single-node)

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --version 3.8.2 \
  --set admissionController.replicas=1 \
  --set backgroundController.replicas=1 \
  --set cleanupController.replicas=1 \
  --set reportsController.replicas=1 \
  --set admissionController.antiAffinity.enabled=false \
  --set backgroundController.antiAffinity.enabled=false \
  --set cleanupController.antiAffinity.enabled=false \
  --set reportsController.antiAffinity.enabled=false \
  --wait
```

**Key flags:**
- `admissionController.replicas=1` + all controller replicas=1 — single-node k3s cannot schedule 3 replicas with default anti-affinity rules
- `antiAffinity.enabled=false` for all controllers — prevents `Pending` pods due to pod anti-affinity requirement (default requires pods on separate nodes, impossible on single-node)
- `--wait` — waits for Kyverno webhooks to be registered before returning; critical because policies applied too early (before webhook is ready) are silently ignored

**Verify Kyverno is running:**
```bash
kubectl get pods -n kyverno
# Expected: 4 pods (admission-controller, background-controller, cleanup-controller, reports-controller) all Running
kubectl get crd clusterpolicies.kyverno.io
# Expected: shows the CRD
```

### Known k3s 1.32.x Compatibility Notes

- No k3s-specific Kyverno conflicts documented in official docs for 1.32.x [MEDIUM confidence — no explicit documentation found]
- k3s uses `containerd` as runtime, which is compatible with Kyverno's admission webhook
- k3s's embedded traefik should not conflict with Kyverno webhooks
- **Potential issue:** k3s system pods (in `kube-system`) are created during cluster bootstrap before Kyverno exists. This is fine because Kyverno webhooks do not affect already-running pods — only new admission requests.
- **Webhook timeout risk:** Default Kyverno webhook timeout is 10 seconds with `Fail` failure policy. On a resource-constrained 6GB VM during install (high CPU/memory load), Kyverno may not respond within 10 seconds to the first few admission requests, causing pod creation failures. Mitigate: install Kyverno policies one at a time after Kyverno is confirmed healthy.

**Confidence:** MEDIUM for k3s compatibility (no explicit documentation; inferred from general Kubernetes compatibility).

---

## Q5: Kyverno 4 Policies

### Install Method

All 4 policies are applied via `kubectl apply -f` with local YAML files. The community policy library provides raw YAML at:
```
https://raw.githubusercontent.com/kyverno/policies/main/<category>/<name>/<name>.yaml
```

**Important:** Download and commit policy YAMLs to `bootstrap/kyverno/` in the repo. Do not apply from URL in production/demo — URL content can change.

### Policy 1: disallow-latest-tag

**Source:** `kyverno/policies/main/best-practices/disallow-latest-tag/disallow-latest-tag.yaml`

**Action required:** Change `validationFailureAction: Audit` to `Enforce` for the thesis demo.

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
spec:
  validationFailureAction: Enforce   # CHANGED from Audit to Enforce
  background: true
  rules:
  - name: require-image-tag
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "An image tag is required."
      foreach:
        - list: "request.object.spec.containers"
          pattern:
            image: "*:*"
        - list: "request.object.spec.initContainers"
          pattern:
            image: "*:*"
        - list: "request.object.spec.ephemeralContainers"
          pattern:
            image: "*:*"
  - name: validate-image-tag
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "Using a mutable image tag e.g. 'latest' is not allowed."
      foreach:
        - list: "request.object.spec.containers"
          pattern:
            image: "!*:latest"
        - list: "request.object.spec.initContainers"
          pattern:
            image: "!*:latest"
        - list: "request.object.spec.ephemeralContainers"
          pattern:
            image: "!*:latest"
```

**CRITICAL:** The demoapp image is `host.rancher-desktop.internal:5001/demoapp:6af2848` — this has a SHA tag, NOT `:latest`. It will **pass** this policy. Verify before switching to Enforce: `kubectl describe pod -n demoapp | grep Image:` — must show `:6af2848` not `:latest`.

System component images (ArgoCD, Kyverno) also use version tags, not `:latest` (they follow semver). They will pass this policy.

### Policy 2: restrict-image-registries

**Source:** `kyverno/policies/main/best-practices/restrict-image-registries/restrict-image-registries.yaml`

**Must customize** the registry pattern for this project:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-image-registries
spec:
  validationFailureAction: Audit   # Keep Audit — too many system images from other registries
  background: true
  rules:
  - name: validate-registries
    match:
      any:
      - resources:
          kinds:
          - Pod
          namespaces:
            - demoapp      # scope to demoapp only — system namespaces use docker.io/gcr.io
    validate:
      message: "Images must come from host.rancher-desktop.internal:5001."
      pattern:
        spec:
          containers:
          - image: "host.rancher-desktop.internal:5001/*"
          =(initContainers):
          - image: "host.rancher-desktop.internal:5001/*"
          =(ephemeralContainers):
          - image: "host.rancher-desktop.internal:5001/*"
```

**CRITICAL design decision:** Scope to `namespaces: [demoapp]` only. If applied cluster-wide without namespace scoping, it will block ArgoCD, Kyverno, and k3s system pods from pulling from `docker.io`/`gcr.io`/`ghcr.io` and break the cluster. The thesis demo wants to show that **demoapp images** must come from the local registry — not that all cluster images must.

**Do NOT set `Enforce` on this policy unless namespace-scoped.** Keep `Audit` to avoid blocking system pods.

### Policy 3: disallow-privileged-containers

**Source:** `kyverno/policies/main/pod-security/baseline/disallow-privileged-containers/disallow-privileged-containers.yaml`

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged-containers
spec:
  validationFailureAction: Audit   # Audit — demoapp runs as root but NOT privileged; important distinction
  background: true
  rules:
  - name: privileged-containers
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "Privileged mode is disallowed."
      pattern:
        spec:
          =(initContainers):
            - =(securityContext):
                =(privileged): "false"
          =(ephemeralContainers):
            - =(securityContext):
                =(privileged): "false"
          containers:
            - =(securityContext):
                =(privileged): "false"
```

**Note:** The demoapp runs as `root` (no `runAsUser` or `USER` directive), but it does NOT set `privileged: true` in securityContext. These are different: running as root user ≠ privileged container mode. The demoapp will **pass** `disallow-privileged-containers` but would fail a `disallow-root-user` policy (which we do not install).

### Policy 4: require-resource-limits

The community policy is actually named `require-requests-limits` (in `best-practices/require-pod-requests-limits/`). The ROADMAP references it as "require-resource-limits" — use the actual community policy, renaming the `metadata.name` to `require-resource-limits` for clarity if desired.

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
spec:
  validationFailureAction: Audit
  background: true
  rules:
  - name: validate-resources
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "CPU and memory resource requests and memory limits are required for containers."
      pattern:
        spec:
          containers:
          - resources:
              requests:
                memory: "?*"
                cpu: "?*"
              limits:
                memory: "?*"
          =(initContainers):
          - resources:
              requests:
                memory: "?*"
                cpu: "?*"
              limits:
                memory: "?*"
          =(ephemeralContainers):
          - resources:
              requests:
                memory: "?*"
                cpu: "?*"
              limits:
                memory: "?*"
```

**Note:** The demoapp deployment (`deploy/base/deployment.yaml`) already has:
```yaml
resources:
  requests: {cpu: "100m", memory: "128Mi"}
  limits: {cpu: "500m", memory: "256Mi"}
```
The demoapp pod will **pass** this policy.

### Validation Failure Action Summary

| Policy | Recommended Action | Reason |
|--------|-------------------|--------|
| `disallow-latest-tag` | **Enforce** | Core thesis demo; demoapp uses SHA tag so it passes |
| `restrict-image-registries` | **Audit** | Must be namespace-scoped; too risky to Enforce cluster-wide |
| `disallow-privileged-containers` | **Audit** | Demoapp passes but ArgoCD/system pods may not; safe in Audit |
| `require-resource-limits` | **Audit** | Some system pods lack explicit limits; Audit avoids breaking cluster |

### Applying All 4 Policies

Create directory `bootstrap/kyverno/` with the 4 YAML files, then:
```bash
kubectl apply -f bootstrap/kyverno/
```

### Demonstrate Policy Enforcement (GITOPS-04 / GITOPS-06)

```bash
# Test: apply a pod with :latest tag — should be BLOCKED (Enforce mode)
kubectl run test-latest --image=nginx:latest -n demoapp --restart=Never
# Expected: Error from server: admission webhook "validate.kyverno.svc-fail" denied the request
# Message: "Using a mutable image tag e.g. 'latest' is not allowed."

# Cleanup
kubectl delete pod test-latest -n demoapp --ignore-not-found
```

**Confidence:** HIGH for policy YAML content (fetched from official raw GitHub). HIGH for policy logic. MEDIUM for exact Enforce behavior of restrict-image-registries (namespace scoping must be empirically confirmed).

---

## Q6: PolicyReport

### What it is

Kyverno automatically creates `PolicyReport` (namespaced) and `ClusterPolicyReport` (cluster-scoped) CRDs. They are populated by:
1. **Admission time** — when a resource is admitted/denied
2. **Background scan** — periodic scan of existing resources (even those that predate Kyverno)

### Commands

```bash
# List all PolicyReports in demoapp namespace
kubectl get policyreport -n demoapp
# Or use short alias:
kubectl get polr -n demoapp

# Wide output shows PASS/FAIL/WARN counts
kubectl get polr -n demoapp -o wide

# See full details of a specific report
kubectl get polr <report-name> -n demoapp -o yaml

# Filter for failures only
kubectl get polr <report-name> -n demoapp -o jsonpath='{.results[?(@.result=="fail")]}'
```

### Expected Output Format

```
NAME                                   KIND         NAME      PASS  FAIL  WARN  ERROR  SKIP
cpol-disallow-latest-tag-<uid>         Deployment   demoapp   2     0     0     0      0
cpol-require-resource-limits-<uid>     Deployment   demoapp   1     0     0     0      0
```

PolicyReport names are auto-generated. The `KIND` column shows the evaluated resource type; `NAME` shows the resource instance. PASS counts reflect rules that passed.

### Triggering Background Scan Refresh

After installing Kyverno and policies, the background controller scans existing resources. This typically completes within 1-2 minutes. To confirm:
```bash
kubectl get polr -n demoapp --watch
```

### Demo command for GITOPS-06

```bash
# Show all policy results for demoapp namespace resources
kubectl get polr -n demoapp -o wide

# Then show detailed results in YAML for thesis committee
kubectl get polr -n demoapp -o yaml | grep -A5 "result:"
```

**Confidence:** HIGH — PolicyReport behavior is standard Kyverno 1.10+ behavior, confirmed from official docs.

---

## Q7: Port-Forward and Admin Password

### Port-Forward

```bash
kubectl port-forward svc/argocd-server -n argocd 8443:443
```

Then open `https://localhost:8443` in the browser. The self-signed TLS certificate will show a browser warning — accept it (expected for local setup).

**Note:** On Windows, run this command in a dedicated terminal window — it blocks while active.

### Admin Password Retrieval

Two methods (both work in ArgoCD v3.x):

**Method 1 — kubectl direct (no ArgoCD CLI required):**
```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

**Method 2 — ArgoCD CLI (if installed):**
```bash
argocd admin initial-password -n argocd
```

**Secret name:** `argocd-initial-admin-secret` — unchanged in v3.x. [HIGH confidence]

**Login credentials:** username `admin`, password from above command.

**After first login:** Change the password via the ArgoCD UI (Settings → User Management → admin → Update Password), then delete the initial secret:
```bash
kubectl delete secret argocd-initial-admin-secret -n argocd
```

### v3.4-Specific Notes

No changes to admin password mechanism in v3.3→v3.4. The `argocd-initial-admin-secret` secret name and base64-encoded `password` field are stable across v3.x. [HIGH confidence — confirmed from stable docs]

**Confidence:** HIGH.

---

## Q8: Known Pitfalls in 2026

### Pitfall 1: ArgoCD/Kyverno Sync Loop (HIGH risk)

**What happens:** After Kyverno installs, it may add annotations or claim managed fields on the demoapp Deployment. ArgoCD then sees the live state as different from Git and syncs. Kyverno mutates again. Repeat — app never reaches stable `Synced` state.

**Prevention:**
1. Add `ignoreDifferences` with `managedFieldsManagers: [kyverno, kyverno-background-controller, kube-controller-manager]` to the Application CR before installing Kyverno
2. Add `syncOptions: [RespectIgnoreDifferences=true]` to the Application syncPolicy
3. If still flapping after 5 minutes, inspect: `kubectl get application demoapp -n argocd -o yaml` — look at `status.conditions` and `status.operationState.syncResult` for the specific field causing OutOfSync

**Empirical check:** After installing both ArgoCD and Kyverno, run:
```bash
watch kubectl get application demoapp -n argocd
```
Status should stabilize at `Synced / Healthy` within 2-3 minutes. If it oscillates between Synced and OutOfSync, the ignoreDifferences config needs refinement.

### Pitfall 2: restrict-image-registries Breaks System Pods (HIGH risk)

**What happens:** If `restrict-image-registries` is applied cluster-wide with `Enforce` mode, any new pod from `docker.io` (including ArgoCD pod restarts, Kyverno CRD updates) will be denied. Cluster enters broken state.

**Prevention:** ALWAYS namespace-scope this policy to `demoapp` namespace only. Keep `Audit` mode.

### Pitfall 3: Kyverno Anti-Affinity Prevents Scheduling (MEDIUM risk)

**What happens:** Default Kyverno Helm chart has `podAntiAffinity` rules requiring controllers to run on separate nodes. Single-node k3s cannot satisfy this — pods stay `Pending` indefinitely.

**Prevention:** `--set admissionController.antiAffinity.enabled=false` (and same for all other controllers) in the helm install command. The install command above includes this.

### Pitfall 4: ImagePullBackOff After First ArgoCD Sync (MEDIUM risk)

**What happens:** ArgoCD Application CR points to `deploy/overlays/local/`. The current image tag in `demoapp-patch.yaml` is `6af2848`. If the registry has been restarted (e.g., Rancher Desktop restarted), this image may no longer be available in the local registry. ArgoCD syncs, pod restart fails with `ImagePullBackOff`.

**Prevention before applying Application CR:**
```bash
# Verify the image still exists in registry
curl http://localhost:5001/v2/demoapp/tags/list
# Expected output: {"name":"demoapp","tags":["6af2848"]}
```
If empty, rebuild and push with `app/build.sh` before proceeding.

### Pitfall 5: Kyverno Webhook Timeout on First Install (LOW-MEDIUM risk)

**What happens:** On a loaded 6GB VM during install, Kyverno's admission webhook may not respond within 10 seconds (default timeout). New pod admission requests fail with `context deadline exceeded`.

**Prevention:**
- Install Kyverno with `--wait` flag to ensure all controllers are Ready before returning
- Add a 60-second pause after Kyverno Helm install before applying policies
- If pods fail to start after Kyverno install: check `kubectl get pods -n kyverno` and wait for all 4 pods to be `Running 1/1`

### Pitfall 6: ArgoCD Manages demoapp Namespace Ownership (LOW risk)

**What happens:** The `demoapp` namespace already exists (created in Phase 2). If the Application CR specifies `CreateNamespace=true` or manages the namespace, ArgoCD may try to annotate it and conflict with the existing annotation-free namespace.

**Prevention:** Set `CreateNamespace=false` (or omit the syncOption entirely since namespace exists). The Application CR above uses `CreateNamespace=false`.

### Pitfall 7: ArgoCD Server-Side Apply Conflict with Kyverno (LOW risk for this setup)

**What happens:** If `ServerSideApply=true` is set on the Application AND Kyverno mutates fields, field ownership conflicts can cause sync failures with `Apply failed: ... field is owned by kyverno`.

**Prevention:** Do NOT add `ServerSideApply=true` to the Application syncOptions. Use default client-side apply.

### Pitfall 8: Kyverno policies shipped in `Audit` mode don't show in PolicyReport immediately (LOW)

**What happens:** After applying policies, `kubectl get polr -n demoapp` shows nothing or old reports.

**Cause:** Background controller scans on a schedule (default: periodic, usually under 2 min). There is no immediate scan trigger via kubectl.

**Workaround:** Wait ~2 minutes after policy apply, then check. Or restart the background controller pod to force an immediate scan:
```bash
kubectl rollout restart deployment/kyverno-background-controller -n kyverno
```

---

## Standard Stack

| Component | Version | Helm Chart | Source |
|-----------|---------|-----------|--------|
| ArgoCD | v3.4.4 | argo-cd 10.1.0 | `argo/argo-cd` repo |
| Kyverno | v1.18.2 | kyverno 3.8.2 | `kyverno/kyverno` repo |
| Kustomize | bundled in ArgoCD | n/a | No separate install needed |

### Repository Commands

```bash
# Add repos
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# Verify versions available
helm search repo argo/argo-cd --versions | grep "10.1.0"
helm search repo kyverno/kyverno --versions | grep "3.8.2"
```

---

## Architecture Patterns

### Directory Structure for Phase 3

```
bootstrap/
├── argocd/
│   └── application.yaml          # ArgoCD Application CR — apply once
└── kyverno/
    ├── disallow-latest-tag.yaml  # From kyverno/policies repo, modified to Enforce
    ├── restrict-image-registries.yaml  # Customized: namespace-scoped to demoapp
    ├── disallow-privileged-containers.yaml  # From kyverno/policies repo
    └── require-resource-limits.yaml  # From kyverno/policies repo (renamed)

deploy/                           # Already exists from Phase 2 — unchanged
├── base/
│   ├── namespace.yaml
│   ├── deployment.yaml           # Has resource limits (will pass require-resource-limits)
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays/local/
    ├── demoapp-patch.yaml        # Currently: image: ...demoapp:6af2848
    └── kustomization.yaml
```

### Self-Heal Demonstration Procedure (GITOPS-05)

```bash
# 1. Confirm ArgoCD shows Synced/Healthy
kubectl get application demoapp -n argocd

# 2. Manually edit the deployment (directly violates GitOps)
kubectl edit deployment demoapp -n demoapp
# Change: image: host.rancher-desktop.internal:5001/demoapp:6af2848
# To:     image: host.rancher-desktop.internal:5001/demoapp:WRONGTAG

# 3. Watch ArgoCD detect and revert the drift (default sync interval: 3 minutes)
watch kubectl get pods -n demoapp
# Within the sync interval, ArgoCD replaces the pod back to 6af2848

# 4. Verify in ArgoCD UI: Application transitions OutOfSync → Syncing → Synced
```

**To reduce sync interval for demo purposes** (optional):
```bash
# In argocd-cm ConfigMap, set:
#   timeout.reconciliation: 30s  (default is 180s / 3 minutes)
kubectl patch configmap argocd-cm -n argocd \
  --patch '{"data": {"timeout.reconciliation": "30s"}}'
```

This makes self-heal visible within 30 seconds — much better for live demo.

---

## Environment Availability

| Dependency | Required By | Available on Windows/WSL2 | Notes |
|------------|-------------|--------------------------|-------|
| helm CLI | ArgoCD + Kyverno install | Must be installed | `winget install Helm.Helm` or via `choco install kubernetes-helm` |
| kubectl | All verification | Available via Rancher Desktop | Bundled with RD |
| curl | Registry verification | Available in WSL2 | `curl http://localhost:5001/v2/demoapp/tags/list` |
| Internet access | Helm chart repos + GitHub raw | Required | Helm repos + kyverno/policies raw YAML |
| ArgoCD CLI | Optional (admin password) | Not required | `kubectl get secret` works without it |

**Install helm on Windows:**
```bash
# From WSL2:
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
# Verify:
helm version
```

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Manual shell-based verification (no automated test suite for infrastructure) |
| Config file | None — kubectl commands as acceptance tests |
| Quick run | `kubectl get pods -n argocd && kubectl get application demoapp -n argocd` |
| Full suite | See Phase Requirements → Test Map below |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GITOPS-01 | ArgoCD pods Running, chart version 10.1.0 | smoke | `helm list -n argocd` + `kubectl get pods -n argocd` | N/A — manual |
| GITOPS-02 | Application shows Synced + Healthy | smoke | `kubectl get application demoapp -n argocd -o jsonpath='{.status.sync.status}'` | N/A — manual |
| GITOPS-03 | Tag change in demoapp-patch.yaml triggers pod replace | integration | edit file → git push → `watch kubectl get pods -n demoapp` | N/A — manual |
| GITOPS-04 | All 4 Kyverno policies present; disallow-latest-tag blocks :latest pods | integration | `kubectl get cpol` + `kubectl run test --image=nginx:latest -n demoapp` | N/A — manual |
| GITOPS-05 | kubectl edit reverted by ArgoCD within sync interval | integration | `kubectl edit` + `watch kubectl get pods -n demoapp` | N/A — manual |
| GITOPS-06 | PolicyReport shows admission results | smoke | `kubectl get polr -n demoapp -o wide` | N/A — manual |

---

## Open Questions

1. **Exact Kyverno managed field manager names**
   - What we know: Controllers are named `kyverno-admission-controller`, `kyverno-background-controller`, `kyverno-reports-controller`
   - What's unclear: The manager name used in `metadata.managedFields[].manager` — it may be the binary name (`kyverno`) or the controller name
   - Recommendation: After install, run `kubectl get deployment demoapp -n demoapp -o jsonpath='{.metadata.managedFields[*].manager}'` and use exact names from output in `ignoreDifferences`

2. **Does the sync loop actually occur with validate-only policies?**
   - What we know: The 4 installed policies are validate rules only (no mutate rules). Kyverno mutating webhooks only fire for policies with mutate rules.
   - What's unclear: Whether Kyverno's reports controller still adds annotations to evaluated resources that cause ArgoCD diff
   - Recommendation: Install with minimal `ignoreDifferences` first, observe for 5 minutes. If no OutOfSync flapping, no additional config needed.

3. **repoURL for local development**
   - What we know: ArgoCD controller runs inside k3s VM; it cannot reach macOS filesystem
   - What's unclear: Whether the GitHub repo URL is public (can be accessed by ArgoCD without credentials) or private (needs a Git credential secret)
   - Recommendation: If repo is public GitHub, no credentials needed. If private, create ArgoCD repository credential secret before applying Application CR.

4. **ArgoCD sync interval for demo**
   - Default: 3 minutes (180s). For thesis demo, consider reducing to 30s.
   - Trade-off: Shorter interval increases ArgoCD repo-server load. On 6GB VM, 30s is fine for a single-app thesis setup.

---

## Sources

### Primary (HIGH confidence)
- ArgoCD official docs `https://argo-cd.readthedocs.io/en/stable/` — Application spec, getting started, sync options, upgrading guide
- ArgoCD Helm chart `Chart.yaml` for 10.1.0 — confirms appVersion v3.4.4
- ArgoCD Helm chart `values.yaml` (raw GitHub) — HA flags, resource defaults
- Kyverno policy library raw YAML (GitHub) — `disallow-latest-tag`, `restrict-image-registries`, `require-pod-requests-limits`
- Kyverno Helm index `kyverno.github.io/kyverno/index.yaml` — chart 3.8.2 = appVersion v1.18.2
- Kyverno official docs `https://kyverno.io/docs/` — PolicyReport, installation, admission webhook settings

### Secondary (MEDIUM confidence)
- ArgoCD upgrade guide 3.3→3.4 — SSA not a new default for application sync
- Kyverno values.yaml (raw GitHub) — single-node antiAffinity flags
- ArgoCD HA docs — inferred resource limits for non-HA

### Tertiary (LOW confidence — verify empirically)
- Kyverno `managedFieldsManagers` names — inferred from component names, not from official docs
- Sync loop behavior with validate-only policies — inferred from general ArgoCD+Kyverno pattern documentation

---

## Metadata

**Confidence breakdown:**
- Standard stack (versions): HIGH — official sources
- ArgoCD Helm install: HIGH — confirmed from chart files
- ArgoCD Application CR: HIGH — official declarative setup docs
- Server-Side Apply defaults: HIGH — upgrade guide is definitive
- ignoreDifferences for Kyverno: MEDIUM — mechanism confirmed, exact field names need empirical check
- Kyverno install: HIGH — official docs + Helm index
- Policy YAMLs: HIGH — fetched from official GitHub raw
- PolicyReport behavior: HIGH — official docs
- Kyverno/k3s 1.32.x compat: MEDIUM — no k3s-specific docs found; general compatibility inferred
- RAM estimates: MEDIUM — conservative targets; actuals vary

**Research date:** 2026-07-23
**Valid until:** 2026-09-01 (stable components; check Kyverno chart release if delaying past that)
