#!/usr/bin/env bash
# bootstrap/kyverno/kyverno-install.sh
# Install Kyverno v1.18.2 (Helm chart kyverno 3.8.2) — single-node config.
# Run from repo root on the Windows/WSL2 target machine.
# REQUIRES: ArgoCD from 03-01 already running and showing Synced/Healthy.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*"; exit 1; }

echo "── DevSecOps Pipeline — Phase 3: Kyverno Install ───────────────────────"

# ── Pre-flight ────────────────────────────────────────────────────────────────
kubectl get nodes --no-headers 2>/dev/null | grep -q "Ready" \
  || die "k3s not Ready. Start Rancher Desktop first."
ok "k3s cluster Ready"

ARGO_SYNC=$(kubectl get application demoapp -n argocd \
  -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "missing")
if [ "${ARGO_SYNC}" != "Synced" ]; then
  warn "ArgoCD Application 'demoapp' is not Synced (status: ${ARGO_SYNC}). Kyverno may induce a sync loop if ArgoCD is not healthy."
  warn "Run: bash bootstrap/argocd/argocd-install.sh and kubectl apply -f bootstrap/argocd/application.yaml first."
  warn "Continuing anyway — press Ctrl+C within 5s to abort."
  sleep 5
fi
ok "ArgoCD pre-flight check passed"

# ── Helm repo ─────────────────────────────────────────────────────────────────
echo "── Adding kyverno Helm repo ─────────────────────────────────────────────"
helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
helm repo update kyverno

# ── Install ───────────────────────────────────────────────────────────────────
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

ok "Kyverno installed"
echo ""
kubectl get pods -n kyverno

# ── Wait for webhook stabilisation ───────────────────────────────────────────
echo ""
echo "── Waiting 60s for webhook registration to stabilize ───────────────────"
warn "(Prevents webhook timeout on first policy apply)"
sleep 60

# ── Apply policies ────────────────────────────────────────────────────────────
echo "── Applying 4 ClusterPolicies ───────────────────────────────────────────"
kubectl apply -f bootstrap/kyverno/disallow-latest-tag.yaml
kubectl apply -f bootstrap/kyverno/restrict-image-registries.yaml
kubectl apply -f bootstrap/kyverno/disallow-privileged-containers.yaml
kubectl apply -f bootstrap/kyverno/require-resource-limits.yaml

echo ""
echo "── ClusterPolicies present ──────────────────────────────────────────────"
kubectl get clusterpolicy

# ── Trigger immediate PolicyReport ───────────────────────────────────────────
echo ""
echo "── Restarting background controller to trigger PolicyReport scan ────────"
kubectl rollout restart deployment/kyverno-background-controller -n kyverno
ok "Background controller restarted"
echo ""
warn "Wait 2-3 minutes for PolicyReport to populate, then:"
echo "  kubectl get polr -n demoapp -o wide"
echo ""
echo "── Next: verify admission blocking ─────────────────────────────────────"
echo "  kubectl run test-latest --image=nginx:latest -n demoapp --restart=Never"
echo "  Expected: admission webhook denied (mutable image tag)"
