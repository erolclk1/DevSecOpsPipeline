#!/usr/bin/env bash
# bootstrap/argocd/argocd-install.sh
# Install ArgoCD v3.4.4 (Helm chart argo-cd 10.1.0) — non-HA, single-node.
# Run from repo root on the Windows/WSL2 target machine.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*"; exit 1; }

echo "── DevSecOps Pipeline — Phase 3: ArgoCD Install ────────────────────────"

# ── Pre-flight ────────────────────────────────────────────────────────────────
kubectl get nodes --no-headers 2>/dev/null | grep -q "Ready" \
  || die "k3s not Ready. Start Rancher Desktop first."
ok "k3s cluster Ready"

command -v helm &>/dev/null || die "helm not found. Install from https://helm.sh"
ok "helm found: $(helm version --short 2>/dev/null)"

# ── Helm repo ─────────────────────────────────────────────────────────────────
echo "── Adding argo Helm repo ────────────────────────────────────────────────"
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo

# ── Install ───────────────────────────────────────────────────────────────────
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

ok "ArgoCD installed"
echo ""
kubectl get pods -n argocd

# ── Reduce sync interval to 30s for live demo ─────────────────────────────────
echo ""
echo "── Setting sync interval to 30s ────────────────────────────────────────"
kubectl patch configmap argocd-cm -n argocd \
  --patch '{"data": {"timeout.reconciliation": "30s"}}'
ok "Sync interval set to 30s"

# ── Access info ───────────────────────────────────────────────────────────────
echo ""
echo "── ArgoCD UI access ─────────────────────────────────────────────────────"
echo "  Run in a separate terminal (keep it open):"
echo "  kubectl port-forward svc/argocd-server -n argocd 8443:443"
echo ""
echo "── Admin credentials ────────────────────────────────────────────────────"
echo -n "  Password: "
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
echo "  Username: admin"
echo "  URL: https://localhost:8443  (accept the self-signed TLS warning)"
echo ""
echo "── Next: apply the Application CR ──────────────────────────────────────"
echo "  kubectl apply -f bootstrap/argocd/application.yaml"
