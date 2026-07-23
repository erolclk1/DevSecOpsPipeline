#!/usr/bin/env bash
# bootstrap/argocd/verify.sh — Verify Phase 3 ArgoCD success criteria
#
# Run AFTER argocd-install.sh AND apply.sh complete successfully.
# Run from Git Bash (Windows) or Terminal (macOS):
#   bash bootstrap/argocd/verify.sh

REGISTRY_HOST="host.rancher-desktop.internal"
REGISTRY_PORT="5001"
PASS=0; FAIL=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}✗${NC} $*"; FAIL=$((FAIL + 1)); }
info() { echo -e "${YELLOW}→${NC} $*"; }

echo "── Phase 3 ArgoCD Verification ──────────────────────────────────────────"

# ── SC1: ArgoCD Application Synced + Healthy ──────────────────────────────────
SYNC=$(kubectl get application demoapp -n argocd \
  -o jsonpath='{.status.sync.status}' 2>/dev/null)
HEALTH=$(kubectl get application demoapp -n argocd \
  -o jsonpath='{.status.health.status}' 2>/dev/null)
if [[ "${SYNC}" == "Synced" && "${HEALTH}" == "Healthy" ]]; then
  ok "SC1: ArgoCD Application demoapp → sync=Synced health=Healthy"
else
  fail "SC1: ArgoCD Application demoapp → sync=${SYNC:-missing} health=${HEALTH:-missing}"
  info "  Check: kubectl get application demoapp -n argocd -o yaml"
fi

# ── SC2: demoapp pod running with registry image ───────────────────────────────
POD_IMAGE=$(kubectl get pods -n demoapp \
  -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null)
if echo "${POD_IMAGE}" | grep -q "${REGISTRY_HOST}:${REGISTRY_PORT}/demoapp:"; then
  ok "SC2: demoapp pod running image from local registry: ${POD_IMAGE}"
else
  fail "SC2: demoapp pod image unexpected: '${POD_IMAGE}'"
  info "  Expected: ${REGISTRY_HOST}:${REGISTRY_PORT}/demoapp:<sha>"
fi

# ── SC3: bootstrap/argocd/application.yaml committed ─────────────────────────
if git show HEAD -- bootstrap/argocd/application.yaml &>/dev/null || \
   git log --oneline -- bootstrap/argocd/application.yaml 2>/dev/null | grep -q .; then
  ok "SC3: bootstrap/argocd/application.yaml committed to git"
else
  fail "SC3: bootstrap/argocd/application.yaml not found in git history"
fi

# ── SC4: Helm chart version correct ───────────────────────────────────────────
CHART=$(helm list -n argocd --filter argocd -o json 2>/dev/null \
  | python3 -c "import sys,json; r=json.load(sys.stdin); print(r[0]['chart'] if r else '')" 2>/dev/null)
if [[ "${CHART}" == "argo-cd-10.1.0" ]]; then
  ok "SC4: ArgoCD Helm chart version: ${CHART}"
else
  fail "SC4: ArgoCD chart version unexpected: '${CHART:-not found}'"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "── Results ──────────────────────────────────────────────────────────────"
echo -e "  ${GREEN}Passed: ${PASS}/4${NC}   ${RED}Failed: ${FAIL}/4${NC}"

if [ "${FAIL}" -eq 0 ]; then
  echo -e "\n${GREEN}Phase 3 ArgoCD COMPLETE ✓${NC}"
  echo "  ArgoCD UI: https://localhost:8443 (port-forward required)"
  echo ""
  echo "  Manual demos to run:"
  echo "    Self-heal: kubectl edit deployment demoapp -n demoapp (change tag → reverts in 30s)"
  echo "    Git-push:  edit deploy/overlays/local/demoapp-patch.yaml, push → pod replaces"
  echo ""
  echo "  Next: make phase-3-kyverno"
  exit 0
else
  echo -e "\n${RED}Phase 3 ArgoCD incomplete — ${FAIL} check(s) failed. Fix issues above and re-run.${NC}"
  exit 1
fi
