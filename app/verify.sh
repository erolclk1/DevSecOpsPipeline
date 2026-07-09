#!/usr/bin/env bash
# app/verify.sh — Verify Phase 2 success criteria
#
# Run AFTER app/build.sh AND app/deploy.sh complete successfully.
# Run from Git Bash (Windows) or Terminal (macOS):
#   bash app/verify.sh

REGISTRY_HOST="host.rancher-desktop.internal"
REGISTRY_PORT="5000"
NODEPORT="30080"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PASS=0; FAIL=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}✗${NC} $*"; FAIL=$((FAIL + 1)); }
info() { echo -e "${YELLOW}→${NC} $*"; }

echo "── Phase 2 Vulnerable App Verification ─────────────────────────────────"

# Load TAG
ENV_FILE="${REPO_ROOT}/.env.phase2"
if [ -f "${ENV_FILE}" ]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi
TAG="${TAG:-$(git rev-parse --short HEAD 2>/dev/null)}"
IMAGE="${REGISTRY_HOST}:${REGISTRY_PORT}/demoapp:${TAG}"

# ── SC1: Trivy finds CRITICAL CVEs ───────────────────────────────────────────
info "SC1: Trivy scan of ${IMAGE}..."
trivy image --severity HIGH,CRITICAL --exit-code 1 --no-progress "${IMAGE}" &>/dev/null
TRIVY_EXIT=$?
if [ "${TRIVY_EXIT}" -ne 0 ]; then
  ok "SC1: Trivy found CRITICAL CVEs (exit ${TRIVY_EXIT}) — vulnerable image confirmed"
else
  fail "SC1: Trivy reported 0 CRITICAL CVEs — base image or DB wrong"
  info "  Run: trivy image --severity HIGH,CRITICAL ${IMAGE}"
fi

# ── SC2: Pod running as root ──────────────────────────────────────────────────
POD=$(kubectl get pod -n demoapp -l app=demoapp -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "${POD}" ]; then
  fail "SC2: No pod found in namespace demoapp — run app/deploy.sh first"
else
  WHOAMI=$(kubectl exec "${POD}" -n demoapp -- whoami 2>/dev/null)
  if [ "${WHOAMI}" = "root" ]; then
    ok "SC2: kubectl exec ${POD} -- whoami → root"
  else
    fail "SC2: whoami returned '${WHOAMI}' (expected 'root')"
    info "  Check Dockerfile — USER directive must be absent"
  fi
fi

# ── SC3: SQL injection proof ──────────────────────────────────────────────────
info "SC3: Testing SQL injection endpoint..."
SQLI_RESP=$(curl -sf --connect-timeout 5 \
  "http://localhost:${NODEPORT}/sqli?user=%27+OR+%271%27%3D%271" 2>/dev/null)
if echo "${SQLI_RESP}" | grep -qE '"error"|"query"'; then
  ok "SC3: /sqli returned SQL error/query evidence — injection confirmed"
  info "  Response: $(echo "${SQLI_RESP}" | head -c 200)"
else
  fail "SC3: /sqli response does not prove injection (got: '${SQLI_RESP}')"
  info "  Expected: response containing 'error' or 'query' field with the injected string"
  info "  Check: curl \"http://localhost:${NODEPORT}/sqli?user=' OR '1'='1\""
fi

# ── SC4: Command injection proof ──────────────────────────────────────────────
info "SC4: Testing command injection endpoint..."
CMD_RESP=$(curl -sf --connect-timeout 5 \
  "http://localhost:${NODEPORT}/cmd?input=id" 2>/dev/null)
if echo "${CMD_RESP}" | grep -q "uid=0(root)"; then
  ok "SC4: /cmd?input=id → uid=0(root) — command injection confirmed"
  info "  Response: $(echo "${CMD_RESP}" | head -c 200)"
else
  fail "SC4: /cmd response does not contain uid=0(root) (got: '${CMD_RESP}')"
  info "  Check: curl \"http://localhost:${NODEPORT}/cmd?input=id\""
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "── Results ──────────────────────────────────────────────────────────────"
echo -e "  ${GREEN}Passed: ${PASS}/4${NC}   ${RED}Failed: ${FAIL}/4${NC}"

if [ "${FAIL}" -eq 0 ]; then
  echo -e "\n${GREEN}Phase 2 Vulnerable App COMPLETE ✓${NC}"
  echo "  Image:    ${IMAGE}"
  echo "  NodePort: localhost:${NODEPORT}"
  echo "  Pod:      ${POD}"
  echo ""
  echo "  Next: proceed to Phase 3 (ArgoCD + Kyverno)"
  exit 0
else
  echo -e "\n${RED}Phase 2 incomplete — ${FAIL} check(s) failed. Fix issues above and re-run.${NC}"
  exit 1
fi
