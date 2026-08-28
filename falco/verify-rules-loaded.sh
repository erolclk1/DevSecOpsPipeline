#!/usr/bin/env bash
# falco/verify-rules-loaded.sh — Wave 0 rules-load smoke test
#
# Asserts:
#   - Falco pod exists
#   - Falco pod is Running
#   - modern_ebpf initialization is present
#   - no startup rule errors
#   - custom-rules.yaml exists
#   - all 6 custom rules are present

set -uo pipefail

PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok() {
  echo -e "${GREEN}✓${NC} $*"
  PASS=$((PASS + 1))
}

fail() {
  echo -e "${RED}✗${NC} $*"
  FAIL=$((FAIL + 1))
}

info() {
  echo -e "${YELLOW}→${NC} $*"
}

echo "── Falco Rules-Load Verification ───────────────────────────────────────"

# ── 1. Resolve Falco pod ─────────────────────────────────────────────────────

POD=$(kubectl get pod \
  -n falco \
  -l app.kubernetes.io/name=falco \
  -o jsonpath='{.items[0].metadata.name}' \
  2>/dev/null)

if [ -z "${POD}" ]; then
  fail "No Falco pod found in namespace falco"
  echo ""
  echo -e "  ${RED}Passed: ${PASS}   Failed: ${FAIL}${NC}"
  exit 1
fi

ok "Falco pod resolved: ${POD}"

# ── 2. Pod Running ───────────────────────────────────────────────────────────

PHASE=$(kubectl get pod \
  -n falco \
  "${POD}" \
  -o jsonpath='{.status.phase}' \
  2>/dev/null)

if [ "${PHASE}" = "Running" ]; then
  ok "Pod phase is Running (FALCO-01: driver did not CrashLoop)"
else
  fail "Pod phase is '${PHASE}' (expected 'Running')"
  info "kubectl describe pod -n falco ${POD}"
fi

# ── 3. Startup logs ──────────────────────────────────────────────────────────

LOGS=$(kubectl logs -n falco "${POD}" 2>&1)

if echo "${LOGS}" | grep -Eq "modern_ebpf|Falco initialized"; then
  ok "Driver evidence found in logs (modern_ebpf / Falco initialized)"
else
  fail "No modern_ebpf / initialization evidence in Falco logs"
  info "kubectl logs -n falco ${POD} | grep -iE 'ebpf|initialized'"
fi

# ── 4. Rule parse errors ─────────────────────────────────────────────────────

if echo "${LOGS}" | grep -Eiq \
  "unknown macro|unknown list|rule .* has an invalid|Error.*rule|parse error"; then

  fail "Rule parse errors detected in Falco startup logs"

  info "kubectl logs -n falco ${POD} | grep -iE 'unknown macro|unknown list|invalid|parse error|Error'"

else
  ok "Zero rule parse errors in startup logs (FALCO-03)"
fi

# ── 5. Locate custom rules file ───────────────────────────────────────────────

RULE_FILE="/etc/falco/rules.d/custom-rules.yaml"

echo "Checking custom rules file inside Falco pod..."

if kubectl exec \
  -n falco \
  "${POD}" \
  -- sh -c "test -f '${RULE_FILE}'" \
  >/dev/null 2>&1; then

  ok "Custom rules file found: ${RULE_FILE}"

else
  fail "Custom rules file does not exist: ${RULE_FILE}"
  info "kubectl exec -n falco ${POD} -- sh -c \"ls -la /etc/falco/rules.d/\""
fi

# ── 6. Verify every custom rule definition ────────────────────────────────────

RULE_NAMES=(
  "Reverse Shell Tool in demoapp"
  "Stdio to Network in demoapp"
  "Shell Spawned by Web App in demoapp"
  "Read Sensitive File in demoapp"
  "Package Management in demoapp"
  "Contact K8s API Server from demoapp"
)

for name in "${RULE_NAMES[@]}"; do

  if kubectl exec \
    -n falco \
    "${POD}" \
    -- sh -c "grep -F -- 'rule: ${name}' '${RULE_FILE}' >/dev/null 2>&1"; then

    ok "Rule definition found: ${name}"

  else

    fail "Rule definition NOT found: ${name}"

  fi

done

# ── 7. Summary ────────────────────────────────────────────────────────────────

echo ""
echo "── Results ──────────────────────────────────────────────────────────────"
echo -e "  ${GREEN}Passed: ${PASS}${NC}   ${RED}Failed: ${FAIL}${NC}"

if [ "${FAIL}" -eq 0 ]; then
  echo -e "\n${GREEN}Falco rules loaded correctly ✓${NC}"
  exit 0
else
  echo -e "\n${RED}Falco rules verification failed — ${FAIL} check(s) failed.${NC}"
  exit 1
fi