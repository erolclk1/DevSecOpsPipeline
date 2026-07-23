#!/usr/bin/env bash
# bootstrap/argocd/apply.sh — Apply ArgoCD Application CR and wait for Synced/Healthy
#
# PREREQUISITE: argocd-install.sh ran successfully
#
# Run from Git Bash (Windows) or Terminal (macOS):
#   bash bootstrap/argocd/apply.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*"; exit 1; }

echo "── DevSecOps Pipeline — Phase 3: Apply ArgoCD Application CR ───────────"

# ── Pre-flight ─────────────────────────────────────────────────────────────────
kubectl get pods -n argocd --no-headers 2>/dev/null | grep -q "Running" \
  || die "ArgoCD pods not running. Run: make phase-3 first."
ok "ArgoCD pods running"

# Confirm image tag is in registry
TAG=$(grep 'image:' "${REPO_ROOT}/deploy/overlays/local/demoapp-patch.yaml" \
  | grep -oE '[^:]+$' | tr -d ' ')
echo "  Current image tag: ${TAG}"
curl -sf "http://localhost:5001/v2/demoapp/tags/list" 2>/dev/null | grep -q "${TAG}" \
  || { warn "Tag ${TAG} not found in registry — ArgoCD sync will get ImagePullBackOff"; \
       warn "Run: bash app/build.sh to rebuild first"; }

# ── Apply Application CR ───────────────────────────────────────────────────────
echo "── Applying ArgoCD Application CR ───────────────────────────────────────"
kubectl apply -f "${SCRIPT_DIR}/application.yaml"
ok "Application CR applied"

# ── Wait for sync ──────────────────────────────────────────────────────────────
echo "── Waiting for initial sync (up to 120s) ────────────────────────────────"
for i in $(seq 1 24); do
  SYNC=$(kubectl get application demoapp -n argocd \
    -o jsonpath='{.status.sync.status}' 2>/dev/null)
  HEALTH=$(kubectl get application demoapp -n argocd \
    -o jsonpath='{.status.health.status}' 2>/dev/null)
  if [[ "${SYNC}" == "Synced" && "${HEALTH}" == "Healthy" ]]; then
    ok "ArgoCD Application: sync=${SYNC} health=${HEALTH}"
    break
  fi
  echo -e "  (${i}/24) sync=${SYNC:-Unknown} health=${HEALTH:-Unknown}"
  sleep 5
done

SYNC=$(kubectl get application demoapp -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
HEALTH=$(kubectl get application demoapp -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
if [[ "${SYNC}" != "Synced" || "${HEALTH}" != "Healthy" ]]; then
  warn "Timed out waiting — current: sync=${SYNC} health=${HEALTH}"
  warn "Check: kubectl get application demoapp -n argocd -o yaml"
fi

echo ""
echo "── ArgoCD UI ─────────────────────────────────────────────────────────────"
echo "  Run in a separate terminal: kubectl port-forward svc/argocd-server -n argocd 8443:443"
echo "  Open: https://localhost:8443"
echo ""
echo "── Next: make verify-phase-3-argocd"
