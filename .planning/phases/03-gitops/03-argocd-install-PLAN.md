---
id: "03-01"
title: "ArgoCD Install + Application CR + Self-Heal Verification"
wave: 1
depends_on: ["02-02"]
requirements_addressed: [GITOPS-01, GITOPS-02, GITOPS-03, GITOPS-05]
files_modified:
  - bootstrap/argocd/argocd-install.sh
  - bootstrap/argocd/application.yaml
  - Makefile
autonomous: false
must_haves:
  truths:
    - "ArgoCD UI at https://localhost:8443 shows Application demoapp Synced and Healthy"
    - "A one-line tag change to deploy/overlays/local/demoapp-patch.yaml pushed to Git causes the demoapp pod to be replaced — no kubectl apply by the operator"
    - "kubectl edit deployment demoapp -n demoapp changing the image tag is automatically reverted by ArgoCD within 30 seconds"
    - "bootstrap/argocd/application.yaml exists in the repo with the correct repoURL, path, and ignoreDifferences config"
  artifacts:
    - path: "bootstrap/argocd/argocd-install.sh"
      provides: "Repeatable ArgoCD Helm install script (non-HA, single-node resource limits)"
      contains: "helm upgrade --install argocd argo/argo-cd --version 10.1.0"
    - path: "bootstrap/argocd/application.yaml"
      provides: "ArgoCD Application CR wiring Git repo to cluster"
      contains: "repoURL: https://github.com/erolclk1/DevSecOpsPipeline"
    - path: "Makefile"
      provides: "argocd-install and verify-phase-3-argocd targets"
      contains: "verify-phase-3-argocd"
  key_links:
    - from: "bootstrap/argocd/application.yaml"
      to: "deploy/overlays/local/kustomization.yaml"
      via: "spec.source.path: deploy/overlays/local"
      pattern: "path: deploy/overlays/local"
    - from: "ArgoCD controller (in-cluster)"
      to: "https://github.com/erolclk1/DevSecOpsPipeline"
      via: "spec.source.repoURL (public repo, no credential needed)"
      pattern: "repoURL: https://github.com/erolclk1/DevSecOpsPipeline"
    - from: "deploy/overlays/local/demoapp-patch.yaml"
      to: "demoapp pod in demoapp namespace"
      via: "ArgoCD Kustomize build + automated sync"
      pattern: "image: host.rancher-desktop.internal:5001/demoapp:"
---

<objective>
Install ArgoCD v3.4.4 on the k3s cluster (non-HA, single-node resource limits), author the Application CR that points ArgoCD at the GitHub mono-repo overlay path, verify the initial sync reaches Synced/Healthy, then demonstrate self-heal by showing that a manual kubectl edit is reverted without any operator action.

Purpose: This is the GitOps thesis proof-of-concept. After this plan, the cluster state is controlled entirely by Git. No human ever runs kubectl apply to deploy demoapp again. ArgoCD owns that boundary from this point forward.

Output: Running ArgoCD in argocd namespace, Application CR in the repo, self-heal confirmed, Makefile targets and install script committed.
</objective>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@CLAUDE.md
@.planning/phases/03-gitops/RESEARCH.md
@.planning/phases/02-vulnerable-app/02-02-SUMMARY.md
@deploy/overlays/local/demoapp-patch.yaml
@deploy/overlays/local/kustomization.yaml
</context>

<tasks>

<task id="1" title="Install ArgoCD v3.4.4 via Helm, create install script, add Makefile targets">
<read_first>
- CLAUDE.md — Critical Rules: registry hostname, Jenkins must not kubectl apply (does not affect this setup task but confirms boundary)
- .planning/phases/03-gitops/RESEARCH.md — Q1 (full helm install command with resource limits), Q7 (port-forward and admin password retrieval)
- Makefile — existing argocd-install target (lines 118-129); will be replaced by the richer script
</read_first>
<action>
**Target machine: Windows with Rancher Desktop 1.23.1 running (WSL2 backend). All kubectl and helm commands run from WSL2 or Windows Git Bash.**

**Step 1 — Pre-flight check: verify the demoapp image still exists in registry.**

Before installing anything, confirm the image tag `6af2848` is still in the local registry. If Rancher Desktop was restarted since Phase 2, the registry container may have been recreated without its data (if no persistent volume was used).

```bash
curl http://localhost:5001/v2/demoapp/tags/list
# Expected: {"name":"demoapp","tags":["6af2848"]}
```

If the response is empty or returns an error, rebuild and push the image first:
```bash
bash app/build.sh
```

**Step 2 — Create bootstrap/argocd/ directory and argocd-install.sh.**

Create the file `bootstrap/argocd/argocd-install.sh` with the following content exactly:

```bash
#!/usr/bin/env bash
# bootstrap/argocd/argocd-install.sh
# Install ArgoCD v3.4.4 (Helm chart argo-cd 10.1.0) — non-HA, single-node.
# Run from repo root on the Windows/WSL2 target machine.
set -euo pipefail

echo "── Adding argo Helm repo ────────────────────────────────────────────────"
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo

echo "── Installing ArgoCD 10.1.0 (appVersion v3.4.4) ────────────────────────"
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

echo ""
echo "✓ ArgoCD installed. Verify all pods are Running:"
kubectl get pods -n argocd

echo ""
echo "── Reduce sync interval to 30s for live demo ───────────────────────────"
kubectl patch configmap argocd-cm -n argocd \
  --patch '{"data": {"timeout.reconciliation": "30s"}}'
echo "✓ Sync interval set to 30s"

echo ""
echo "── Access the ArgoCD UI ─────────────────────────────────────────────────"
echo "  Run in a separate terminal (blocks while active):"
echo "  kubectl port-forward svc/argocd-server -n argocd 8443:443"
echo ""
echo "── Retrieve admin password ──────────────────────────────────────────────"
echo -n "  Password: "
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
echo "  Username: admin"
echo "  URL: https://localhost:8443  (accept the self-signed TLS warning)"
```

Make it executable: `chmod +x bootstrap/argocd/argocd-install.sh`

**Step 3 — Run the install script.**

```bash
bash bootstrap/argocd/argocd-install.sh
```

Wait for `--wait` to return (typically 2-3 minutes on a 6GB VM). If any pod is stuck in Pending or CrashLoopBackOff, check events: `kubectl describe pod <pod-name> -n argocd`.

**Step 4 — Update Makefile.**

The existing Makefile has a basic `argocd-install` target that is incomplete (missing dex disable, resource limits, sync interval patch). Replace the existing Phase 3 ArgoCD section and add the verify target. Find the section starting with `## Install ArgoCD v3.4.4` and replace through `echo "✓ ArgoCD installed"` with the following:

```makefile
## Install ArgoCD v3.4.4 (non-HA, dex disabled, resource limits, 30s sync)
argocd-install:
	@bash bootstrap/argocd/argocd-install.sh

## Verify Phase 3 ArgoCD success criteria
verify-phase-3-argocd:
	@echo "── Phase 3 ArgoCD Verification ──────────────────────────────────────"
	@echo "1. Helm chart installed:"
	@helm list -n argocd --filter argocd
	@echo "2. All pods Running:"
	@kubectl get pods -n argocd
	@echo "3. Application sync status:"
	@kubectl get application demoapp -n argocd \
	  -o jsonpath='  sync={.status.sync.status} health={.status.health.status}' 2>/dev/null && echo || echo "  Application CR not yet applied"
	@echo "4. demoapp pod image tag:"
	@kubectl get pods -n demoapp -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null || echo "  demoapp pods not found"
	@echo ""
	@echo "Manual checks required:"
	@echo "  a) https://localhost:8443 — ArgoCD UI shows demoapp Synced + Healthy"
	@echo "  b) Self-heal: kubectl edit deployment demoapp -n demoapp (change tag) → reverts within 30s"
```

Also add `verify-phase-3-argocd` to the `.PHONY` line.

**Step 5 — Commit argocd-install.sh and Makefile changes.**

```bash
git add bootstrap/argocd/argocd-install.sh Makefile
git commit -m "feat(phase-3): add argocd-install.sh and verify-phase-3-argocd Makefile target"
```
</action>
<acceptance_criteria>
- `helm list -n argocd` shows release `argocd` with chart `argo-cd-10.1.0` and STATUS `deployed`
- `kubectl get pods -n argocd` shows 4 pods all in Running state: argocd-application-controller, argocd-repo-server, argocd-server, argocd-redis (and argocd-applicationset-controller)
- `kubectl rollout status deployment/argocd-server -n argocd` exits 0 — "successfully rolled out"
- `kubectl get configmap argocd-cm -n argocd -o jsonpath='{.data.timeout\.reconciliation}'` returns `30s`
- `bootstrap/argocd/argocd-install.sh` is committed to git and executable
- Admin password is retrievable: `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d` prints a non-empty string
</acceptance_criteria>
</task>

<task id="2" title="Author bootstrap/argocd/application.yaml and verify initial Synced/Healthy state">
<read_first>
- .planning/phases/03-gitops/RESEARCH.md — Q2 (full Application CR YAML with ignoreDifferences), Q3 (sync loop risk and ignoreDifferences mechanism), Q8 Pitfall 4 (ImagePullBackOff if image tag not in registry)
- deploy/overlays/local/demoapp-patch.yaml — confirms current image tag is 6af2848
- deploy/overlays/local/kustomization.yaml — confirms Kustomize overlay structure ArgoCD will build
</read_first>
<action>
**Target machine: Windows/WSL2. Run all commands from repo root.**

**Step 1 — Create bootstrap/argocd/application.yaml.**

Create the file with the following content exactly. The `ignoreDifferences` block is pre-configured to handle Kyverno managed fields (installed in plan 03-02). Including it now prevents a sync loop when Kyverno is added later.

```yaml
# bootstrap/argocd/application.yaml
# ArgoCD Application CR — apply once to argocd namespace.
# Watches deploy/overlays/local/ in the GitHub repo.
# Auto-sync with selfHeal and prune enabled.
#
# CRITICAL: This file is the ONLY mechanism for changing cluster state.
# Jenkins MUST NOT kubectl apply. ArgoCD owns cluster deployments.
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
    repoURL: https://github.com/erolclk1/DevSecOpsPipeline.git
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

**Why `CreateNamespace=false`:** The `demoapp` namespace already exists from Phase 2. ArgoCD must not attempt to recreate or annotate-manage it.

**Why `kustomize: {}`:** An empty map tells ArgoCD to auto-detect the `kustomization.yaml` in the path and invoke its bundled kustomize binary. No separate kustomize install needed.

**Why `RespectIgnoreDifferences=true`:** Without this, ArgoCD ignores the `ignoreDifferences` block during sync (only skips it during diff). This combination prevents a Kyverno-induced sync loop after plan 03-02.

**Do NOT add `ServerSideApply=true`** to syncOptions. SSA is not a default in ArgoCD v3.4 for application syncs, and adding it interacts unexpectedly with Kyverno field management.

**Step 2 — Verify image tag still in registry before applying.**

```bash
curl http://localhost:5001/v2/demoapp/tags/list
# Must contain: "6af2848"
```

If missing, run `bash app/build.sh` first.

**Step 3 — Apply the Application CR.**

```bash
kubectl apply -f bootstrap/argocd/application.yaml
```

Expected output: `application.argoproj.io/demoapp created`

**Step 4 — Watch initial sync.**

Open a separate terminal for the port-forward (must stay running):
```bash
kubectl port-forward svc/argocd-server -n argocd 8443:443
```

In a second terminal, watch the Application status transition:
```bash
watch kubectl get application demoapp -n argocd
```

Expected progression: `Unknown` or `OutOfSync` → `Syncing` → `Synced`. Health column: `Missing` or `Progressing` → `Healthy`. This typically takes 60-90 seconds on first sync.

If it shows `OutOfSync` for more than 3 minutes after initial sync completed, run:
```bash
kubectl get application demoapp -n argocd -o yaml | grep -A20 "conditions:"
```
Look for the specific field causing drift. If it is a Kyverno annotation (unlikely at this stage before Kyverno is installed), add the annotation key as a `jsonPointers` entry in `ignoreDifferences`.

**Step 5 — Verify in ArgoCD UI.**

Open `https://localhost:8443` in a browser. Accept the self-signed TLS warning. Log in with username `admin` and the password from Task 1. The `demoapp` Application tile must show green `Synced` and green `Healthy`.

**Step 6 — Commit application.yaml.**

```bash
git add bootstrap/argocd/application.yaml
git commit -m "feat(phase-3): add ArgoCD Application CR for demoapp GitOps sync"
```
</action>
<acceptance_criteria>
- `kubectl get application demoapp -n argocd -o jsonpath='{.status.sync.status}'` returns `Synced`
- `kubectl get application demoapp -n argocd -o jsonpath='{.status.health.status}'` returns `Healthy`
- ArgoCD UI at https://localhost:8443 shows the demoapp tile with Synced (green) and Healthy (green) — screenshot this for thesis evidence
- `kubectl get pods -n demoapp` shows the demoapp pod in `Running` state with image tag containing `6af2848`
- `bootstrap/argocd/application.yaml` is committed to git
- The Application CR `spec.source.repoURL` is `https://github.com/erolclk1/DevSecOpsPipeline.git` (not a local path)
</acceptance_criteria>
</task>

<task id="3" title="Demonstrate GitOps self-heal: kubectl edit is reverted by ArgoCD">
<read_first>
- .planning/phases/03-gitops/RESEARCH.md — Q3 Self-Heal Demonstration Procedure (exact kubectl edit steps, watch command)
- .planning/REQUIREMENTS.md — GITOPS-05 (self-heal requirement), GITOPS-03 (tag-change-triggers-pod-replace requirement)
</read_first>
<action>
**Target machine: Windows/WSL2. The port-forward from Task 2 must still be running.**

This task demonstrates both GITOPS-05 (self-heal) and validates GITOPS-03 (Git commit → pod replace). Run both sub-demonstrations and capture evidence.

**Sub-demo A: Self-heal (GITOPS-05)**

1. Confirm baseline — ArgoCD shows Synced/Healthy:
   ```bash
   kubectl get application demoapp -n argocd
   ```

2. Violate GitOps directly by editing the live Deployment:
   ```bash
   kubectl edit deployment demoapp -n demoapp
   ```
   In the editor that opens, find the line:
   ```
   image: host.rancher-desktop.internal:5001/demoapp:6af2848
   ```
   Change it to:
   ```
   image: host.rancher-desktop.internal:5001/demoapp:WRONGTAG
   ```
   Save and exit the editor.

3. Watch ArgoCD detect and revert the drift. In a separate terminal:
   ```bash
   watch kubectl get pods -n demoapp
   ```
   Within 30 seconds (the patched sync interval), ArgoCD will detect the Deployment diverges from Git, re-apply the desired state from `deploy/overlays/local/`, and replace the pod.

4. Verify reversion:
   ```bash
   kubectl get pods -n demoapp
   kubectl describe pod -n demoapp | grep "Image:"
   ```
   The image tag must return to `6af2848`.

5. Check ArgoCD UI — the Application status should cycle `OutOfSync → Syncing → Synced` and return to `Healthy`.

**Sub-demo B: Git-push triggers pod replace (GITOPS-03)**

This sub-demo requires the demoapp image to have a second tag in the registry. Check what tags are available:
```bash
curl http://localhost:5001/v2/demoapp/tags/list
```

If there is only one tag (`6af2848`), use a dummy second tag to demonstrate the mechanism (ArgoCD will sync but pod will enter ImagePullBackOff — that is acceptable for the demonstration; the key proof is that ArgoCD synced without any kubectl apply):
```bash
# Tag the existing image with a test tag
docker tag localhost:5001/demoapp:6af2848 localhost:5001/demoapp:demo-test
docker push localhost:5001/demoapp:demo-test
```

Edit `deploy/overlays/local/demoapp-patch.yaml` — change the image tag from `6af2848` to `demo-test`:
```yaml
image: host.rancher-desktop.internal:5001/demoapp:demo-test
```

Commit and push:
```bash
git add deploy/overlays/local/demoapp-patch.yaml
git commit -m "test(phase-3): demonstrate GitOps tag-change sync"
git push origin main
```

Within 30 seconds, watch ArgoCD detect the new commit and sync:
```bash
watch kubectl get application demoapp -n argocd
```

After confirming the demonstration, revert back to `6af2848`:
```bash
# Edit demoapp-patch.yaml back to 6af2848
git add deploy/overlays/local/demoapp-patch.yaml
git commit -m "revert(phase-3): restore demoapp tag to 6af2848 after sync demo"
git push origin main
```

Wait for ArgoCD to re-sync to `6af2848` and return to Healthy before proceeding to plan 03-02.
</action>
<acceptance_criteria>
- Self-heal confirmed: after `kubectl edit` changes the image tag to `WRONGTAG`, the demoapp pod is reverted to `6af2848` within 30 seconds — no kubectl apply by the operator
- ArgoCD UI shows `OutOfSync → Syncing → Synced` cycle during self-heal
- Git-push demo confirmed: pushing a tag change to `demoapp-patch.yaml` causes ArgoCD to sync — visible in `kubectl get application demoapp -n argocd` status change
- Final state: `deploy/overlays/local/demoapp-patch.yaml` is restored to `6af2848` and ArgoCD shows Synced/Healthy
- Screenshot or note of ArgoCD self-heal cycle captured as thesis evidence (GITOPS-05 proof)
- `make verify-phase-3-argocd` runs without errors and shows Synced + Healthy status
</acceptance_criteria>
</task>

</tasks>

## Verification

**Phase 3 ArgoCD must_haves check:**

```bash
# 1. ArgoCD chart version correct
helm list -n argocd --filter argocd -o json | python3 -c "import sys,json; r=json.load(sys.stdin)[0]; print('PASS' if r['chart']=='argo-cd-10.1.0' else 'FAIL: got '+r['chart'])"

# 2. All ArgoCD pods running
kubectl get pods -n argocd --no-headers | awk '{if($3!="Running") print "FAIL:",$1,$3; else print "PASS:",$1}'

# 3. Application sync status
kubectl get application demoapp -n argocd -o jsonpath='sync={.status.sync.status} health={.status.health.status}' && echo
# Expected: sync=Synced health=Healthy

# 4. demoapp pod running with correct tag
kubectl get pods -n demoapp -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}'
# Expected: host.rancher-desktop.internal:5001/demoapp:6af2848

# 5. bootstrap/argocd/application.yaml committed
git show HEAD -- bootstrap/argocd/application.yaml | head -5
```

**Manual checks (human required):**
- ArgoCD UI at https://localhost:8443 shows green Synced + green Healthy for demoapp application
- Self-heal demonstration was observed in the ArgoCD UI (status cycle recorded)

<output>
After completing all three tasks and their acceptance criteria, create `.planning/phases/03-gitops/03-argocd-install-SUMMARY.md` with:

1. **What was built** — ArgoCD version, chart version, namespace, Application CR path, sync interval
2. **Key files created** — list of all files created or modified with one-line description each
3. **Phase 3 ArgoCD success criteria** — table with each SC, the check command, and PASS/FAIL result
4. **Decisions made** — any empirical findings (e.g., whether sync loop occurred, actual managedFields manager names observed, any ignoreDifferences tuning needed)
5. **Thesis evidence** — note the ArgoCD UI screenshot location and self-heal cycle observation
6. **Self-check: PASSED** — written only if all three tasks' acceptance criteria are met
</output>
