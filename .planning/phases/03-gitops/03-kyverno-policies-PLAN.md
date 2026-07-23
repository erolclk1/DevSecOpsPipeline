---
id: "03-02"
title: "Kyverno Install + 4 Policies + Admission Blocking Demo"
wave: 2
depends_on: ["03-01"]
requirements_addressed: [GITOPS-04, GITOPS-06]
files_modified:
  - bootstrap/kyverno/kyverno-install.sh
  - bootstrap/kyverno/disallow-latest-tag.yaml
  - bootstrap/kyverno/restrict-image-registries.yaml
  - bootstrap/kyverno/disallow-privileged-containers.yaml
  - bootstrap/kyverno/require-resource-limits.yaml
  - Makefile
autonomous: false
must_haves:
  truths:
    - "kubectl get clusterpolicy shows all 4 policies: disallow-latest-tag, restrict-image-registries, disallow-privileged-containers, require-resource-limits"
    - "kubectl run test-latest --image=nginx:latest -n demoapp is denied at admission with a message about mutable image tags"
    - "kubectl get polr -n demoapp -o wide shows PASS counts for all 4 policies against the demoapp deployment"
    - "ArgoCD Application demoapp remains Synced and Healthy after Kyverno is installed (no sync loop)"
  artifacts:
    - path: "bootstrap/kyverno/kyverno-install.sh"
      provides: "Repeatable Kyverno Helm install script with single-node anti-affinity flags"
      contains: "helm upgrade --install kyverno kyverno/kyverno --version 3.8.2"
    - path: "bootstrap/kyverno/disallow-latest-tag.yaml"
      provides: "ClusterPolicy blocking :latest image tags — Enforce mode"
      contains: "validationFailureAction: Enforce"
    - path: "bootstrap/kyverno/restrict-image-registries.yaml"
      provides: "ClusterPolicy scoped to demoapp namespace only — Audit mode"
      contains: "namespaces:\n            - demoapp"
    - path: "bootstrap/kyverno/disallow-privileged-containers.yaml"
      provides: "ClusterPolicy blocking privileged: true containers — Audit mode"
      contains: "validationFailureAction: Audit"
    - path: "bootstrap/kyverno/require-resource-limits.yaml"
      provides: "ClusterPolicy requiring CPU and memory requests+limits — Audit mode"
      contains: "validationFailureAction: Audit"
    - path: "Makefile"
      provides: "kyverno-install and verify-phase-3-kyverno targets"
      contains: "verify-phase-3-kyverno"
  key_links:
    - from: "bootstrap/kyverno/disallow-latest-tag.yaml"
      to: "Pod admission in all namespaces"
      via: "Kyverno admission webhook (validate.kyverno.svc-fail)"
      pattern: "validationFailureAction: Enforce"
    - from: "bootstrap/kyverno/restrict-image-registries.yaml"
      to: "Pod admission in demoapp namespace only"
      via: "Kyverno namespaces match condition"
      pattern: "namespaces:\n            - demoapp"
    - from: "ArgoCD Application demoapp"
      to: "Kyverno managed fields"
      via: "ignoreDifferences.managedFieldsManagers (pre-configured in 03-01)"
      pattern: "managedFieldsManagers"
---

<objective>
Install Kyverno v1.18.2 (chart 3.8.2) on the k3s cluster with single-node scheduling adjustments, apply 4 community ClusterPolicies with the correct enforcement modes and namespace scoping, demonstrate that admission blocking works for :latest tags, confirm ArgoCD does not enter a sync loop, and verify PolicyReport shows evaluation results for all 4 policies.

Purpose: Kyverno is the admission control layer of the three-layer thesis. This plan proves that the cluster rejects non-compliant workloads at the gate, independent of the CI pipeline. The Kyverno/ArgoCD sync loop risk is the highest technical risk in Phase 3 — the ignoreDifferences config from plan 03-01 is already in place as prevention.

Output: 4 running ClusterPolicies, admission blocking confirmed, PolicyReport populated, Makefile targets committed.
</objective>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@CLAUDE.md
@.planning/phases/03-gitops/RESEARCH.md
@deploy/base/deployment.yaml
@.planning/phases/03-gitops/03-argocd-install-PLAN.md
</context>

<tasks>

<task id="1" title="Install Kyverno v1.18.2 via Helm, create install script and policy YAML files">
<read_first>
- .planning/phases/03-gitops/RESEARCH.md — Q4 (Kyverno Helm install command with all antiAffinity flags), Q5 (all 4 policy YAMLs with exact field names and validationFailureAction values), Q8 Pitfall 2 (restrict-image-registries cluster-wide breaks system pods), Pitfall 3 (antiAffinity prevents scheduling on single-node), Pitfall 5 (webhook timeout on first install)
- deploy/base/deployment.yaml — confirms demoapp has resource limits (will PASS require-resource-limits)
</read_first>
<action>
**Target machine: Windows/WSL2. Run from repo root. ArgoCD from plan 03-01 must be running and showing Synced/Healthy before starting.**

**Step 1 — Create bootstrap/kyverno/ directory and kyverno-install.sh.**

Create `bootstrap/kyverno/kyverno-install.sh` with the following content exactly:

```bash
#!/usr/bin/env bash
# bootstrap/kyverno/kyverno-install.sh
# Install Kyverno v1.18.2 (Helm chart kyverno 3.8.2) — single-node config.
# Run from repo root on the Windows/WSL2 target machine.
# REQUIRES: ArgoCD from 03-01 already running (ArgoCD ignoreDifferences
#           pre-configured to handle Kyverno managed fields).
set -euo pipefail

echo "── Adding kyverno Helm repo ─────────────────────────────────────────────"
helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
helm repo update kyverno

echo "── Installing Kyverno 3.8.2 (appVersion v1.18.2) ───────────────────────"
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

echo ""
echo "✓ Kyverno installed. Verify all pods are Running:"
kubectl get pods -n kyverno

echo ""
echo "── Waiting 60s for webhook registration to stabilize ───────────────────"
echo "   (Prevents webhook timeout on first policy apply)"
sleep 60

echo ""
echo "── Applying 4 ClusterPolicies ───────────────────────────────────────────"
kubectl apply -f bootstrap/kyverno/

echo ""
echo "── Verifying policies are present ──────────────────────────────────────"
kubectl get clusterpolicy

echo ""
echo "── Restarting background controller to trigger immediate PolicyReport ──"
kubectl rollout restart deployment/kyverno-background-controller -n kyverno
echo "   Wait 2-3 minutes for PolicyReport to populate, then:"
echo "   kubectl get polr -n demoapp -o wide"
```

Make it executable: `chmod +x bootstrap/kyverno/kyverno-install.sh`

**Step 2 — Create the 4 policy YAML files.**

Create `bootstrap/kyverno/disallow-latest-tag.yaml`:

```yaml
# bootstrap/kyverno/disallow-latest-tag.yaml
# Blocks pods with :latest image tag or no tag.
# validationFailureAction: Enforce — this is the primary demo-critical policy.
# The demoapp image uses tag :6af2848 (SHA) — it PASSES this policy.
# System images (ArgoCD, Kyverno) use semver tags — they also PASS.
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
spec:
  validationFailureAction: Enforce
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

Create `bootstrap/kyverno/restrict-image-registries.yaml`:

```yaml
# bootstrap/kyverno/restrict-image-registries.yaml
# Requires demoapp namespace pods to use images from host.rancher-desktop.internal:5001.
#
# CRITICAL SCOPING: namespaces: [demoapp] — NOT cluster-wide.
# Applying cluster-wide with Enforce would block ArgoCD, Kyverno, and k3s
# system pods from pulling from docker.io/gcr.io/ghcr.io, breaking the cluster.
# Keep validationFailureAction: Audit — Audit mode records violations without
# blocking, which is sufficient to show policy evaluation in PolicyReport.
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-image-registries
spec:
  validationFailureAction: Audit
  background: true
  rules:
  - name: validate-registries
    match:
      any:
      - resources:
          kinds:
          - Pod
          namespaces:
            - demoapp
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

Create `bootstrap/kyverno/disallow-privileged-containers.yaml`:

```yaml
# bootstrap/kyverno/disallow-privileged-containers.yaml
# Blocks containers with privileged: true in securityContext.
# NOTE: The demoapp runs as root (no USER directive) but does NOT set
# privileged: true — running as root user != privileged container mode.
# The demoapp pod PASSES this policy. Keep Audit to avoid blocking system
# pods that may use privileged mode (e.g., Falco DaemonSet in Phase 5).
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged-containers
spec:
  validationFailureAction: Audit
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

Create `bootstrap/kyverno/require-resource-limits.yaml`:

```yaml
# bootstrap/kyverno/require-resource-limits.yaml
# Requires all pods to declare CPU and memory requests and memory limits.
# The demoapp deployment.yaml already has:
#   requests: {cpu: "100m", memory: "128Mi"}
#   limits: {cpu: "500m", memory: "256Mi"}
# The demoapp pod PASSES this policy.
# Keep Audit — some k3s system pods lack explicit resource declarations.
# Source: community policy require-pod-requests-limits, renamed for clarity.
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

**Step 3 — Run the install script.**

```bash
bash bootstrap/kyverno/kyverno-install.sh
```

The script includes a 60-second pause after Helm install before applying policies. This prevents webhook timeout errors on the first admission requests.

**Step 4 — Add Makefile targets.**

Add the following to the Makefile in the Phase 3 section, after the existing ArgoCD targets:

```makefile
## Install Kyverno v1.18.2 with 4 ClusterPolicies
kyverno-install:
	@bash bootstrap/kyverno/kyverno-install.sh

## Verify Phase 3 Kyverno success criteria
verify-phase-3-kyverno:
	@echo "── Phase 3 Kyverno Verification ─────────────────────────────────────"
	@echo "1. Helm chart installed:"
	@helm list -n kyverno --filter kyverno
	@echo "2. All Kyverno pods Running:"
	@kubectl get pods -n kyverno
	@echo "3. ClusterPolicies present:"
	@kubectl get clusterpolicy -o wide
	@echo "4. PolicyReport in demoapp namespace:"
	@kubectl get polr -n demoapp -o wide 2>/dev/null || echo "  No PolicyReports yet — wait 2-3 minutes for background scan"
	@echo "5. ArgoCD still Synced after Kyverno install:"
	@kubectl get application demoapp -n argocd \
	  -o jsonpath='  sync={.status.sync.status} health={.status.health.status}' && echo
	@echo ""
	@echo "Manual check required:"
	@echo "  Test :latest blocking: kubectl run test-latest --image=nginx:latest -n demoapp --restart=Never"
	@echo "  Expected: admission webhook denied the request (mutable image tag)"
```

Also add `kyverno-install` and `verify-phase-3-kyverno` to the `.PHONY` line.

**Step 5 — Commit all files.**

```bash
git add bootstrap/kyverno/ Makefile
git commit -m "feat(phase-3): add Kyverno install script and 4 ClusterPolicies"
```
</action>
<acceptance_criteria>
- `helm list -n kyverno` shows release `kyverno` with chart `kyverno-3.8.2` and STATUS `deployed`
- `kubectl get pods -n kyverno` shows 4 pods all Running: kyverno-admission-controller, kyverno-background-controller, kyverno-cleanup-controller, kyverno-reports-controller
- `kubectl get clusterpolicy` lists all 4 policies: `disallow-latest-tag`, `restrict-image-registries`, `disallow-privileged-containers`, `require-resource-limits`
- `kubectl get clusterpolicy disallow-latest-tag -o jsonpath='{.spec.validationFailureAction}'` returns `Enforce`
- `kubectl get clusterpolicy restrict-image-registries -o jsonpath='{.spec.rules[0].match.any[0].resources.namespaces[0]}'` returns `demoapp` (namespace-scoped)
- All 4 policy YAML files exist in `bootstrap/kyverno/` and are committed to git
- `bootstrap/kyverno/kyverno-install.sh` is committed and executable
</acceptance_criteria>
</task>

<task id="2" title="Demonstrate Kyverno admission blocking and verify PolicyReport">
<read_first>
- .planning/phases/03-gitops/RESEARCH.md — Q5 (demonstrate policy enforcement commands, exact expected error message), Q6 (PolicyReport commands and expected output format), Q8 Pitfall 1 (ArgoCD sync loop — monitor now that Kyverno is installed), Pitfall 8 (PolicyReport may take 2 min to populate)
- .planning/REQUIREMENTS.md — GITOPS-04 (4 policies present + :latest blocked), GITOPS-06 (PolicyReport shows admission decisions)
</read_first>
<action>
**Target machine: Windows/WSL2. Kyverno from Task 1 must be running.**

**Step 1 — Check ArgoCD has not entered a sync loop.**

With Kyverno now installed, its background controller may add annotations or managed fields to the demoapp Deployment. The `ignoreDifferences` config in the Application CR (set in plan 03-01) should prevent a sync loop.

```bash
# Watch for 3 minutes; status must NOT oscillate between Synced and OutOfSync
watch kubectl get application demoapp -n argocd
```

If the status oscillates after initial sync, diagnose the specific field causing drift:
```bash
kubectl get application demoapp -n argocd -o yaml | grep -A10 "operationState:"
```

If Kyverno annotations are the cause, update `bootstrap/argocd/application.yaml` to add jsonPointers:
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

Apply the updated Application CR: `kubectl apply -f bootstrap/argocd/application.yaml`

Also check actual manager names on the Deployment to confirm the exact names to use in `ignoreDifferences`:
```bash
kubectl get deployment demoapp -n demoapp \
  -o jsonpath='{.metadata.managedFields[*].manager}' && echo
```

Update `managedFieldsManagers` in `application.yaml` to match the exact names observed, then commit and re-apply.

**Step 2 — Demonstrate disallow-latest-tag admission blocking (GITOPS-04).**

```bash
kubectl run test-latest --image=nginx:latest -n demoapp --restart=Never
```

Expected response (the exact message from the policy):
```
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:
resource Pod/demoapp/test-latest was blocked due to the following policies

disallow-latest-tag:
  validate-image-tag: 'validation error: Using a mutable image tag e.g. ''latest'' is not allowed.
    rule validate-image-tag failed at path /spec/containers/0/image/'
```

If the pod is NOT blocked (no error), the webhook is not active. Diagnose:
```bash
kubectl get mutatingwebhookconfiguration | grep kyverno
kubectl get validatingwebhookconfiguration | grep kyverno
```

If webhooks are missing, Kyverno may have installed but webhook registration failed. Re-run:
```bash
bash bootstrap/kyverno/kyverno-install.sh
```

After confirming the block, clean up the test pod if it was somehow created:
```bash
kubectl delete pod test-latest -n demoapp --ignore-not-found
```

**Step 3 — Wait for PolicyReport to populate, then verify (GITOPS-06).**

PolicyReport is populated by Kyverno's background controller scanning existing resources. After the `kyverno-background-controller` rollout restart in the install script, wait 2-3 minutes:

```bash
# Poll until reports appear
kubectl get polr -n demoapp --watch
```

Once populated, check results:
```bash
# Wide view shows PASS/FAIL/WARN counts per policy per resource
kubectl get polr -n demoapp -o wide
```

Expected output (example format — names are auto-generated):
```
NAME                                        KIND         NAME      PASS  FAIL  WARN  ERROR  SKIP
cpol-disallow-latest-tag-<uid>              Deployment   demoapp   2     0     0     0      0
cpol-restrict-image-registries-<uid>        Deployment   demoapp   1     0     0     0      0
cpol-disallow-privileged-containers-<uid>   Deployment   demoapp   1     0     0     0      0
cpol-require-resource-limits-<uid>          Deployment   demoapp   1     0     0     0      0
```

For thesis evidence, capture detailed YAML output:
```bash
kubectl get polr -n demoapp -o yaml | grep -E "(name:|result:|policy:|message:)" | head -40
```

If PolicyReport shows FAIL for `disallow-latest-tag` against the demoapp Deployment, the demoapp pod is using `:latest` — this should not happen since the current tag is `6af2848`. Check:
```bash
kubectl get pods -n demoapp -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}'
```

If PolicyReport shows FAIL for `require-resource-limits`, check that `deploy/base/deployment.yaml` has both `requests` and `limits` defined (it does, per Phase 2 — `requests: {cpu: 100m, memory: 128Mi}` and `limits: {cpu: 500m, memory: 256Mi}`).

**Step 4 — Run verification target.**

```bash
make verify-phase-3-kyverno
```

Review the output and confirm all 5 checks pass.

**Step 5 — Run combined ArgoCD + Kyverno verification.**

```bash
make verify-phase-3-argocd
make verify-phase-3-kyverno
```

Both must pass with ArgoCD showing Synced/Healthy and Kyverno showing 4 policies present with PolicyReport populated.
</action>
<acceptance_criteria>
- `kubectl run test-latest --image=nginx:latest -n demoapp --restart=Never` returns an error containing "mutable image tag" — pod is blocked at admission (GITOPS-04)
- `kubectl get polr -n demoapp -o wide` shows rows for all 4 ClusterPolicies with PASS count > 0 and FAIL count = 0 for the demoapp deployment (GITOPS-06)
- `kubectl get application demoapp -n argocd -o jsonpath='{.status.sync.status}'` returns `Synced` — no sync loop induced by Kyverno (GITOPS-01/GITOPS-02 preserved)
- `kubectl get application demoapp -n argocd -o jsonpath='{.status.health.status}'` returns `Healthy`
- `make verify-phase-3-kyverno` runs without errors
- If `ignoreDifferences` was updated to resolve a sync loop, `bootstrap/argocd/application.yaml` is updated and committed with the empirically confirmed manager names
</acceptance_criteria>
</task>

</tasks>

## Verification

**Phase 3 Kyverno must_haves check:**

```bash
# 1. Kyverno chart version correct
helm list -n kyverno --filter kyverno -o json | python3 -c \
  "import sys,json; r=json.load(sys.stdin)[0]; print('PASS' if r['chart']=='kyverno-3.8.2' else 'FAIL: got '+r['chart'])"

# 2. All 4 policies present
kubectl get clusterpolicy --no-headers | awk '{print $1}' | sort
# Expected (4 lines):
#   disallow-latest-tag
#   disallow-privileged-containers
#   require-resource-limits
#   restrict-image-registries

# 3. disallow-latest-tag in Enforce mode
kubectl get clusterpolicy disallow-latest-tag \
  -o jsonpath='validationFailureAction={.spec.validationFailureAction}' && echo
# Expected: validationFailureAction=Enforce

# 4. restrict-image-registries namespace-scoped to demoapp
kubectl get clusterpolicy restrict-image-registries \
  -o jsonpath='{.spec.rules[0].match.any[0].resources.namespaces}' && echo
# Expected: ["demoapp"]

# 5. Admission blocking works
kubectl run test-latest --image=nginx:latest -n demoapp --restart=Never 2>&1 | \
  grep -q "mutable image tag" && echo "PASS: :latest blocked" || echo "FAIL: :latest not blocked"
kubectl delete pod test-latest -n demoapp --ignore-not-found

# 6. PolicyReport populated
kubectl get polr -n demoapp -o wide

# 7. ArgoCD still healthy after Kyverno install
kubectl get application demoapp -n argocd \
  -o jsonpath='sync={.status.sync.status} health={.status.health.status}' && echo
# Expected: sync=Synced health=Healthy
```

**Manual checks (human required):**
- ArgoCD UI at https://localhost:8443 shows demoapp still green Synced + Healthy after Kyverno install (no sync loop observed)
- Terminal shows admission denied error for :latest test pod (screenshot for thesis evidence)
- `kubectl get polr -n demoapp -o yaml` output captured as thesis evidence for GITOPS-06

**Full Phase 3 success criteria confirmation:**

| SC | Description | Command | Expected |
|----|-------------|---------|---------|
| SC1 | ArgoCD UI Synced + Healthy | `kubectl get application demoapp -n argocd -o jsonpath='{.status.sync.status}'` | `Synced` |
| SC2 | Git push → pod replace (no kubectl apply) | Push tag change to demoapp-patch.yaml, watch pods | Pod replaced within 30s |
| SC3 | kubectl edit reverted by ArgoCD | Edit deployment image tag, watch for revert | Reverted within 30s |
| SC4 | :latest image blocked at admission | `kubectl run test-latest --image=nginx:latest -n demoapp` | Denied — mutable image tag |
| SC5 | PolicyReport shows all 4 policy results | `kubectl get polr -n demoapp -o wide` | 4 rows, PASS > 0 |

<output>
After completing all two tasks and their acceptance criteria, create `.planning/phases/03-gitops/03-kyverno-policies-SUMMARY.md` with:

1. **What was built** — Kyverno version, chart version, namespace, 4 policy names with their validationFailureAction modes
2. **Key files created** — list of all files created or modified with one-line description each
3. **Phase 3 Kyverno success criteria** — table with each SC, the check command, and PASS/FAIL result
4. **Decisions made** — record whether sync loop occurred, exact managedFields manager names observed from the Deployment, any ignoreDifferences tuning required, PolicyReport timing observed
5. **Policy enforcement summary** — for each policy: which resources PASS and FAIL, and why
6. **Thesis evidence** — note the admission blocked screenshot location and PolicyReport YAML output captured
7. **Self-check: PASSED** — written only if all tasks' acceptance criteria are met

Also update `.planning/phases/03-gitops/03-argocd-install-SUMMARY.md` to add a line noting whether the ignoreDifferences config required any updates after Kyverno was installed.
</output>
