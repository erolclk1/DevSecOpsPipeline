#!/usr/bin/env bash
# cluster/verify.sh — Verify Phase 1 Bootstrap success criteria
#
# Run AFTER cluster/setup.sh AND after restarting Rancher Desktop.
# Run from Git Bash (Windows) or Terminal (macOS):
#   bash cluster/verify.sh

REGISTRY_PORT="5000"
REGISTRY_HOST="localhost"
CLUSTER_REGISTRY_HOST="host.rancher-desktop.internal"
SMOKE_IMAGE="${REGISTRY_HOST}:${REGISTRY_PORT}/hello:smoke"
PASS=0; FAIL=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}✗${NC} $*"; FAIL=$((FAIL + 1)); }
info() { echo -e "${YELLOW}→${NC} $*"; }

echo "── Phase 1 Bootstrap Verification ──────────────────────────────────────"

# ── SC1: k3s node Ready ───────────────────────────────────────────────────────
NODE=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | head -1)
if [[ "${NODE}" == "Ready" ]]; then
  ok "SC1: kubectl get nodes → Ready"
else
  fail "SC1: kubectl get nodes → '${NODE:-no output}'"
  info "  Start Rancher Desktop and wait for 'Kubernetes: Running'"
fi

# ── SC2: Registry reachable from host ────────────────────────────────────────
RESP=$(curl -sf --connect-timeout 5 "http://localhost:${REGISTRY_PORT}/v2/" 2>&1)
if echo "${RESP}" | grep -q '{}'; then
  ok "SC2: Registry reachable at localhost:${REGISTRY_PORT}"
else
  fail "SC2: Registry not reachable (got: '${RESP}')"
  info "  Run: docker run -d --restart=always -p 5000:5000 --name registry registry:2"
fi

# ── SC3: Pod can pull image from registry ─────────────────────────────────────
info "SC3: Building and pushing smoke image..."

docker build -q -t "${SMOKE_IMAGE}" - <<'DOCKERFILE'
FROM busybox:1.36.1
CMD ["echo", "hello from local registry"]
DOCKERFILE

if [ $? -ne 0 ]; then
  fail "SC3: docker build failed"
else
  docker push "${SMOKE_IMAGE}" -q 2>/dev/null
  if [ $? -ne 0 ]; then
    fail "SC3: docker push to ${SMOKE_IMAGE} failed"
    info "  Is registry:2 running? Check: docker ps | grep registry"
  else
    kubectl delete pod pull-test --ignore-not-found=true --wait=false 2>/dev/null
    sleep 1
    kubectl run pull-test \
      --image="${SMOKE_IMAGE}" \
      --restart=Never \
      --image-pull-policy=Always 2>/dev/null

    info "Waiting up to 60s for pod..."
    POD_DONE=0
    for i in $(seq 1 12); do
      POD_PHASE=$(kubectl get pod pull-test -o jsonpath='{.status.phase}' 2>/dev/null)
      WAIT_REASON=$(kubectl get pod pull-test -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)

      if [[ "${POD_PHASE}" == "Succeeded" || "${POD_PHASE}" == "Running" ]]; then
        ok "SC3: Pod reached ${POD_PHASE} — image pulled from registry ✓"
        POD_DONE=1; break
      fi
      if [[ "${WAIT_REASON}" == "ImagePullBackOff" || "${WAIT_REASON}" == "ErrImagePull" ]]; then
        fail "SC3: ${WAIT_REASON} — cluster cannot reach ${REGISTRY_HOST}:${REGISTRY_PORT}"
        info "  Check: ~/.rd/k3s/registries.yaml exists and Rancher Desktop was restarted"
        info "  Debug: kubectl describe pod pull-test"
        POD_DONE=1; break
      fi
      info "  (${i}/12) phase=${POD_PHASE:-Pending} reason=${WAIT_REASON:-}"
      sleep 5
    done

    if [ "${POD_DONE}" -eq 0 ]; then
      fail "SC3: Timed out after 60s — phase=$(kubectl get pod pull-test -o jsonpath='{.status.phase}' 2>/dev/null)"
      info "  Debug: kubectl describe pod pull-test"
    fi
    kubectl delete pod pull-test --ignore-not-found=true --wait=false 2>/dev/null
  fi
fi

# ── SC4: Registry reachable from inside cluster ───────────────────────────────
info "SC4: Testing registry access from inside cluster..."
kubectl delete pod curl-test --ignore-not-found=true --wait=false 2>/dev/null
sleep 1
kubectl run curl-test \
  --image=curlimages/curl:8.5.0 \
  --restart=Never \
  -- curl -sf --connect-timeout 10 "http://${CLUSTER_REGISTRY_HOST}:${REGISTRY_PORT}/v2/" 2>/dev/null

SC4_DONE=0
for i in $(seq 1 12); do
  CURL_PHASE=$(kubectl get pod curl-test -o jsonpath='{.status.phase}' 2>/dev/null)
  if [[ "${CURL_PHASE}" == "Succeeded" ]]; then
    CURL_OUT=$(kubectl logs curl-test 2>/dev/null)
    if echo "${CURL_OUT}" | grep -q '{}'; then
      ok "SC4: In-cluster curl → {} (registry reachable from cluster)"
    else
      fail "SC4: In-cluster curl returned '${CURL_OUT}'"
      info "  registries.yaml may not have been picked up — did you restart Rancher Desktop?"
    fi
    SC4_DONE=1; break
  fi
  if [[ "${CURL_PHASE}" == "Failed" ]]; then
    CURL_OUT=$(kubectl logs curl-test 2>/dev/null)
    fail "SC4: curl pod Failed — '${CURL_OUT}'"
    info "  Cluster cannot reach ${CLUSTER_REGISTRY_HOST}:${REGISTRY_PORT}"
    info "  Check: ~/.rd/k3s/registries.yaml  and  rdctl shutdown && rdctl start"
    SC4_DONE=1; break
  fi
  info "  (${i}/12) phase=${CURL_PHASE:-Pending}"
  sleep 5
done

if [ "${SC4_DONE}" -eq 0 ]; then
  fail "SC4: Timed out waiting for curl-test pod"
fi
kubectl delete pod curl-test --ignore-not-found=true --wait=false 2>/dev/null

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "── Results ──────────────────────────────────────────────────────────────"
echo -e "  ${GREEN}Passed: ${PASS}/4${NC}   ${RED}Failed: ${FAIL}/4${NC}"

if [ "${FAIL}" -eq 0 ]; then
  K3S_VER=$(kubectl version 2>/dev/null | grep -i server | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  echo -e "\n${GREEN}Phase 1 Bootstrap COMPLETE ✓${NC}"
  echo "  k3s server: ${K3S_VER:-unknown}"
  echo "  Registry:   ${REGISTRY_HOST}:${REGISTRY_PORT}"
  echo ""
  echo "  Next: proceed to Phase 2"
  exit 0
else
  echo -e "\n${RED}Phase 1 incomplete — ${FAIL} check(s) failed. Fix issues above and re-run.${NC}"
  exit 1
fi
