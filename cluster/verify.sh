#!/usr/bin/env bash
# cluster/verify.sh — Verify Phase 1 Bootstrap success criteria
# Run AFTER cluster/setup.sh AND after restarting Rancher Desktop.
# Usage: bash cluster/verify.sh

set -euo pipefail

REGISTRY_HOST="host.rancher-desktop.internal"
REGISTRY_PORT="5000"
SMOKE_IMAGE="${REGISTRY_HOST}:${REGISTRY_PORT}/hello:smoke"
PASS=0; FAIL=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; ((PASS++)); }
fail() { echo -e "${RED}✗${NC} $*"; ((FAIL++)); }
info() { echo -e "${YELLOW}→${NC} $*"; }

echo "── Phase 1 Bootstrap Verification ──────────────────────────────────────"

# SC1: k3s node Ready
NODE_STATUS=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}')
if echo "${NODE_STATUS}" | grep -q "Ready"; then
  ok "SC1: kubectl get nodes → Ready"
else
  fail "SC1: kubectl get nodes → not Ready (got: ${NODE_STATUS:-none})"
fi

# SC2: Registry reachable from host
if curl -sf "http://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/" | grep -q '{}'; then
  ok "SC2: curl http://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/ → {}"
else
  fail "SC2: Registry not reachable at ${REGISTRY_HOST}:${REGISTRY_PORT}"
  info "  Fallback: try host.lima.internal — update cluster/registries.yaml if it works"
fi

# SC3: Pod can pull from registry
info "SC3: Building and pushing smoke image..."
docker build -t "${SMOKE_IMAGE}" - <<'DOCKERFILE' 2>/dev/null
FROM busybox:1.36.1
CMD ["echo", "hello from local registry"]
DOCKERFILE
docker push "${SMOKE_IMAGE}" 2>/dev/null

kubectl delete pod pull-test --ignore-not-found=true 2>/dev/null
kubectl run pull-test \
  --image="${SMOKE_IMAGE}" \
  --restart=Never \
  --image-pull-policy=Always 2>/dev/null

info "Waiting up to 60s for pod to reach Running/Completed..."
for i in $(seq 1 12); do
  PHASE=$(kubectl get pod pull-test -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
  if [[ "${PHASE}" == "Succeeded" || "${PHASE}" == "Running" ]]; then
    ok "SC3: Pod pull-test reached ${PHASE} — image pulled successfully"
    break
  fi
  if [[ "${PHASE}" == "Failed" ]]; then
    fail "SC3: Pod pull-test Failed — check: kubectl describe pod pull-test"
    break
  fi
  sleep 5
done
kubectl delete pod pull-test --ignore-not-found=true 2>/dev/null

# SC4: Registry reachable from inside the cluster
info "SC4: Checking registry from inside cluster..."
CLUSTER_CURL=$(kubectl run curl-test \
  --image=curlimages/curl:latest \
  --restart=Never \
  --rm \
  -i \
  --command -- curl -s "http://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/" 2>/dev/null || echo "FAILED")

if echo "${CLUSTER_CURL}" | grep -q '{}'; then
  ok "SC4: In-cluster curl → {}"
else
  fail "SC4: In-cluster curl failed (got: ${CLUSTER_CURL})"
  info "  This usually means registries.yaml hostname is wrong."
  info "  Try: host.lima.internal instead of host.rancher-desktop.internal"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "── Results ──────────────────────────────────────────────────────────────"
echo -e "  ${GREEN}Passed: ${PASS}${NC}   ${RED}Failed: ${FAIL}${NC}"

if [[ ${FAIL} -eq 0 ]]; then
  echo -e "\n${GREEN}Phase 1 Bootstrap COMPLETE ✓${NC}"
  echo "  k3s version: $(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}')"
  echo "  Next: /gsd:execute-phase 1  (Wave 2 — pull-verification)"
  exit 0
else
  echo -e "\n${RED}Phase 1 Bootstrap FAILED — fix the issues above before proceeding.${NC}"
  exit 1
fi
