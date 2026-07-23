#!/usr/bin/env bash
# bootstrap/kyverno/verify.sh — Verify Phase 3 Kyverno success criteria
#
# Run AFTER kyverno-install.sh completes and PolicyReport has populated (~3 min).
# Run from Git Bash (Windows) or Terminal (macOS):
#   bash bootstrap/kyverno/verify.sh

PASS=0; FAIL=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}✗${NC} $*"; FAIL=$((FAIL + 1)); }
info() { echo -e "${YELLOW}→${NC} $*"; }

echo "── Phase 3 Kyverno Verification ─────────────────────────────────────────"

# ── SC1: All 4 ClusterPolicies present ────────────────────────────────────────
POLICIES=$(kubectl get clusterpolicy --no-headers 2>/dev/null | awk '{print $1}' | sort)
EXPECTED="disallow-latest-tag disallow-privileged-containers require-resource-limits restrict-image-registries"
FOUND=0
for p in ${EXPECTED}; do
  echo "${POLICIES}" | grep -q "^${p}$" && FOUND=$((FOUND + 1))
done
if [ "${FOUND}" -eq 4 ]; then
  ok "SC1: All 4 ClusterPolicies present"
else
  fail "SC1: Only ${FOUND}/4 ClusterPolicies found (expected: ${EXPECTED})"
  info "  Run: kubectl get clusterpolicy"
fi

# ── SC2: disallow-latest-tag is Enforce ───────────────────────────────────────
ACTION=$(kubectl get clusterpolicy disallow-latest-tag \
  -o jsonpath='{.spec.validationFailureAction}' 2>/dev/null)
if [[ "${ACTION}" == "Enforce" ]]; then
  ok "SC2: disallow-latest-tag validationFailureAction=Enforce"
else
  fail "SC2: disallow-latest-tag validationFailureAction='${ACTION:-missing}' (expected Enforce)"
fi

# ── SC3: restrict-image-registries scoped to demoapp namespace ────────────────
NS=$(kubectl get clusterpolicy restrict-image-registries \
  -o jsonpath='{.spec.rules[0].match.any[0].resources.namespaces[0]}' 2>/dev/null)
if [[ "${NS}" == "demoapp" ]]; then
  ok "SC3: restrict-image-registries scoped to namespace: demoapp"
else
  fail "SC3: restrict-image-registries namespace scope='${NS:-missing}' (expected demoapp)"
  info "  Cluster-wide Enforce would break system pods — must be namespace-scoped"
fi

# ── SC4: :latest admission blocking works ─────────────────────────────────────
info "SC4: Testing :latest admission block (kubectl run test-latest)..."
BLOCK_MSG=$(kubectl run test-latest --image=nginx:latest -n demoapp --restart=Never 2>&1 || true)
kubectl delete pod test-latest -n demoapp --ignore-not-found=true &>/dev/null
if echo "${BLOCK_MSG}" | grep -qi "denied\|mutable image tag\|not allowed"; then
  ok "SC4: :latest image blocked at admission"
  info "  Response: $(echo "${BLOCK_MSG}" | head -c 200)"
else
  fail "SC4: :latest image was NOT blocked (got: '${BLOCK_MSG}')"
  info "  Kyverno webhook may not be active — check: kubectl get validatingwebhookconfiguration | grep kyverno"
fi

# ── SC5: PolicyReport populated for demoapp ───────────────────────────────────
POLR_COUNT=$(kubectl get polr -n demoapp --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "${POLR_COUNT}" -gt 0 ]; then
  ok "SC5: PolicyReport populated in demoapp namespace (${POLR_COUNT} report(s))"
  info "  Run: kubectl get polr -n demoapp -o wide"
else
  fail "SC5: No PolicyReports in demoapp namespace yet"
  info "  Background scan may still be running — wait 2-3 minutes and re-run"
  info "  Or: kubectl rollout restart deployment/kyverno-background-controller -n kyverno"
fi

# ── SC6: ArgoCD still Synced (no sync loop) ────────────────────────────────────
SYNC=$(kubectl get application demoapp -n argocd \
  -o jsonpath='{.status.sync.status}' 2>/dev/null)
HEALTH=$(kubectl get application demoapp -n argocd \
  -o jsonpath='{.status.health.status}' 2>/dev/null)
if [[ "${SYNC}" == "Synced" && "${HEALTH}" == "Healthy" ]]; then
  ok "SC6: ArgoCD still Synced+Healthy after Kyverno install (no sync loop)"
else
  fail "SC6: ArgoCD sync disrupted — sync=${SYNC:-missing} health=${HEALTH:-missing}"
  info "  Kyverno may have added annotations causing drift"
  info "  Check: kubectl get application demoapp -n argocd -o yaml | grep -A10 ignoreDifferences"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "── Results ──────────────────────────────────────────────────────────────"
echo -e "  ${GREEN}Passed: ${PASS}/6${NC}   ${RED}Failed: ${FAIL}/6${NC}"

if [ "${FAIL}" -eq 0 ]; then
  echo -e "\n${GREEN}Phase 3 Kyverno COMPLETE ✓${NC}"
  echo ""
  echo "  Next: proceed to Phase 4 (Jenkins CI)"
  exit 0
else
  echo -e "\n${RED}Phase 3 Kyverno incomplete — ${FAIL} check(s) failed. Fix issues above and re-run.${NC}"
  exit 1
fi
