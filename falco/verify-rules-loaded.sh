#!/usr/bin/env bash
# falco/verify-rules-loaded.sh — Wave 0 rules-load smoke test (FALCO-01, FALCO-03)
#
# Run on the Windows/WSL2 target after `make phase-5`:
#   bash falco/verify-rules-loaded.sh
#
# Asserts: Falco pod is Running (not CrashLoop), driver=modern_ebpf, zero rule
# parse errors, and all 6 custom rule definitions loaded (FALCO-03 reverse-shell
# is fulfilled by rules 1a + 1b, so 6 rule names are expected).

PASS=0; FAIL=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}✗${NC} $*"; FAIL=$((FAIL + 1)); }
info() { echo -e "${YELLOW}→${NC} $*"; }

echo "── Falco Rules-Load Verification ───────────────────────────────────────"

# 1. Resolve the Falco pod
POD=$(kubectl get pod -n falco -l app.kubernetes.io/name=falco -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "${POD}" ]; then
  fail "No Falco pod found in namespace falco (is Falco installed? run 'make phase-5')"
  echo ""
  echo -e "  ${RED}Passed: ${PASS}   Failed: ${FAIL}${NC}"
  exit 1
fi
ok "Falco pod resolved: ${POD}"

# 2. Assert the pod is Running (not CrashLoopBackOff)
PHASE=$(kubectl get pod -n falco "${POD}" -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "${PHASE}" = "Running" ]; then
  ok "Pod phase is Running (FALCO-01: driver did not CrashLoop)"
else
  fail "Pod phase is '${PHASE}' (expected 'Running') — check BTF/modern_ebpf"
  info "  kubectl describe pod -n falco ${POD}"
fi

# 3. Capture startup logs once
LOGS=$(kubectl logs -n falco "${POD}" 2>&1)

# 4. Assert modern_ebpf driver / successful init (FALCO-01)
if echo "${LOGS}" | grep -Eq "modern_ebpf|Falco initialized"; then
  ok "Driver evidence found in logs (modern_ebpf / Falco initialized)"
else
  fail "No modern_ebpf / initialization evidence in Falco logs"
  info "  kubectl logs -n falco ${POD} | grep -iE 'ebpf|initialized'"
fi

# 5. Assert ZERO rule parse errors
if echo "${LOGS}" | grep -Eiq "unknown macro|unknown list|rule .* has an invalid|Error"; then
  fail "Rule parse errors detected in Falco startup logs"
  info "  kubectl logs -n falco ${POD} | grep -iE 'unknown macro|unknown list|Error'"
else
  ok "Zero rule parse errors in startup logs (FALCO-03)"
fi

# 6. Assert all 6 custom rule names loaded (FALCO-03: reverse-shell = 1a + 1b)
RULE_NAMES=(
  "Reverse Shell Tool in demoapp"
  "Stdio to Network in demoapp"
  "Shell Spawned by Web App in demoapp"
  "Read Sensitive File in demoapp"
  "Package Management in demoapp"
  "Contact K8s API Server from demoapp"
)
for name in "${RULE_NAMES[@]}"; do
  if echo "${LOGS}" | grep -qF "${name}"; then
    ok "Rule loaded: ${name}"
  else
    fail "Rule NOT found in logs: ${name}"
  fi
done

# 7. Summary
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
