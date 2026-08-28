#!/usr/bin/env bash
# falco/verify-phase5.sh — Phase 5 end-to-end verification suite
#
# Run on the Windows/WSL2 Rancher Desktop target AFTER `make phase-5`:
#   make verify-phase-5
#   bash falco/verify-phase5.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

echo "── Phase 5 Runtime Security — Full Verification Suite ───────────────────"
echo ""

# ── Step 1: INSTALL/DRIVER ────────────────────────────────────────────────────
echo "── [1/8] Install + Driver check (FALCO-01/FALCO-03) ────────────────────"

if bash "${REPO_ROOT}/falco/verify-rules-loaded.sh"; then
  ok "verify-rules-loaded.sh passed (pod Running, modern_ebpf, 6 rules, zero parse errors)"
else
  fail "verify-rules-loaded.sh failed — cannot continue without a healthy Falco pod"
  echo ""
  echo -e "  ${RED}Passed: ${PASS}   Failed: ${FAIL}${NC}"
  exit 1
fi

echo ""

# ── Step 2: WEBUI ────────────────────────────────────────────────────────────
echo "── [2/8] Falcosidekick webui service (FALCO-02) ────────────────────────"

if kubectl get svc falco-falcosidekick-ui -n falco >/dev/null 2>&1; then
  ok "Service falco-falcosidekick-ui exists in namespace falco"
  info "  To open: kubectl port-forward svc/falco-falcosidekick-ui -n falco 2802:2802"
  info "           then http://localhost:2802"
else
  fail "Service falco-falcosidekick-ui not found — check Falco Helm install"
fi

echo ""

# ── Helper: get current Falco pod ────────────────────────────────────────────
get_falco_pod() {
  kubectl get pod -n falco \
    -l app.kubernetes.io/name=falco \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

# ── Helper: assert alert within 30 seconds ───────────────────────────────────
assert_alert_within_30s() {
  local rule_name="$1"
  local deadline
  local logs=""
  local found=0

  deadline=$(($(date +%s) + 30))

  while [ "$(date +%s)" -lt "${deadline}" ]; do
    logs="$(
      kubectl logs -n falco \
        -l app.kubernetes.io/name=falco \
        --since=300s 2>/dev/null || true
    )"

    if printf '%s\n' "${logs}" | grep -qF "${rule_name}"; then
      found=1
      break
    fi

    sleep 2
  done

  if [ "${found}" -eq 1 ]; then
    ok "Alert fired within 30s: ${rule_name}"
  else
    fail "Alert NOT detected within 30s: ${rule_name}"
    info "  kubectl logs -n falco -l app.kubernetes.io/name=falco --since=300s | grep -F '${rule_name}'"
  fi
}

# ── Step 3: ATK-01 ───────────────────────────────────────────────────────────
echo "── [3/8] ATK-01: SQL injection (exit-0 assertion only) ─────────────────"

info "  SQL injection executes inside the Node.js process."
info "  No syscall/process-spawn is detectable by Falco — asserting sqli.py exits 0 only."

if python3 "${REPO_ROOT}/attacks/sqli.py"; then
  ok "ATK-01: sqli.py exited 0 (SQL injection confirmed, no Falco alert expected)"
else
  fail "ATK-01: sqli.py exited non-zero (app not reachable? check demoapp NodePort 30080)"
fi

echo ""

# ── Step 4: ATK-02 ───────────────────────────────────────────────────────────
echo "── [4/8] ATK-02: Reverse shell trigger ─────────────────────────────────"

bash "${REPO_ROOT}/attacks/reverse_shell.sh" || true

echo "Waiting for Falco alerts (up to 30s each)..."

assert_alert_within_30s "Shell Spawned by Web App in demoapp"
assert_alert_within_30s "Reverse Shell Tool in demoapp"

echo ""

# ── Step 5: ATK-03 ───────────────────────────────────────────────────────────
echo "── [5/8] ATK-03: Privilege probe ───────────────────────────────────────"

bash "${REPO_ROOT}/attacks/privilege_probe.sh" || true

echo "Waiting for Falco alerts (up to 30s each)..."

assert_alert_within_30s "Read Sensitive File in demoapp"
assert_alert_within_30s "Package Management in demoapp"

echo ""

# ── Step 6: PERSISTENCE ──────────────────────────────────────────────────────
echo "── [6/8] Persistence after pod restart (FALCO-02) ──────────────────────"

LOG_NONEMPTY=0

# Windows/WSL2 check.
#
# IMPORTANT:
# Do not use the WSL exit code as the only indication that the file exists.
# Capture the result explicitly.
if wsl -d rancher-desktop -- sh -c "test -s /var/log/falco/events.log" 2>/dev/null; then
  ok "events.log exists and is non-empty on the node (wsl check)"
  LOG_NONEMPTY=1
else
  FALCO_POD="$(get_falco_pod)"

  if [ -n "${FALCO_POD}" ] && \
     kubectl exec -n falco "${FALCO_POD}" -- \
       sh -c "test -s /var/log/falco/events.log" 2>/dev/null; then
    ok "events.log exists and is non-empty inside the Falco pod"
    LOG_NONEMPTY=1
  else
    fail "events.log is empty or not found before restart — alerting pipeline may not be writing to file"
    info "  Check: falco.file_output.enabled=true in falco/values.yaml"
  fi
fi

info "Deleting Falco pod to test persistence..."

kubectl delete pod \
  -n falco \
  -l app.kubernetes.io/name=falco \
  >/dev/null 2>&1 || true

info "Waiting for new Falco pod to reach Running state (up to 90s)..."

READY=0

for i in $(seq 1 18); do
  sleep 5

  NEW_PHASE="$(
    kubectl get pod -n falco \
      -l app.kubernetes.io/name=falco \
      -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true
  )"

  if [ "${NEW_PHASE}" = "Running" ]; then
    READY=1
    ok "New Falco pod is Running after restart"
    break
  fi

  info "  (${i}/18) Pod phase: ${NEW_PHASE:-pending}"
done

if [ "${READY}" -eq 0 ]; then
  fail "New Falco pod did not reach Running within 90s after restart"
fi

if [ "${LOG_NONEMPTY}" -eq 1 ]; then
  if wsl -d rancher-desktop -- \
      sh -c "test -s /var/log/falco/events.log" 2>/dev/null; then

    ok "events.log STILL exists and is non-empty after pod restart (hostPath confirmed)"

  else
    NEW_POD="$(get_falco_pod)"

    if [ -n "${NEW_POD}" ] && \
       kubectl exec -n falco "${NEW_POD}" -- \
         sh -c "test -s /var/log/falco/events.log" 2>/dev/null; then

      ok "events.log STILL exists and is non-empty after pod restart"

    else
      fail "events.log is gone or empty after pod restart — hostPath persistence failed"
    fi
  fi
fi

echo ""

# ── Step 7: RULES AFTER RESTART ───────────────────────────────────────────────
echo "── [7/8] Rules still loaded after pod restart ──────────────────────────"

if bash "${REPO_ROOT}/falco/verify-rules-loaded.sh"; then
  ok "Rules re-verified after pod restart"
else
  fail "Rules not loaded correctly after pod restart"
fi

echo ""

# ── Step 8: ZERO SYSTEM-NAMESPACE DEMO ALERTS ────────────────────────────────
echo "── [8/8] Zero demo alerts from system namespaces (FALCO-04) ────────────"

LEAKED="$(
  kubectl logs \
    -n falco \
    -l app.kubernetes.io/name=falco \
    --since=600s 2>/dev/null |
    grep -E '"tags".*"demo"' |
    grep -E '"ns":"(kube-system|argocd|falco|kube-public)"' ||
    true
)"

if [ -z "${LEAKED}" ]; then
  ok "Zero demo-tagged alerts from kube-system/argocd/falco/kube-public namespaces"
  info "  (Full ops-cycle check: run 'make demo-2' while tailing Falco logs)"
else
  fail "Demo-tagged alerts leaked from system namespaces — check rule namespace scoping"
  info "  Leaked alerts:"
  echo "${LEAKED}" | head -10 | sed 's/^/    /'
fi

echo ""

# ── Final summary ────────────────────────────────────────────────────────────
echo "── Results ──────────────────────────────────────────────────────────────"
echo -e "  ${GREEN}Passed: ${PASS}${NC}   ${RED}Failed: ${FAIL}${NC}"

if [ "${FAIL}" -eq 0 ]; then
  echo ""
  echo -e "${GREEN}Phase 5 verification PASSED ✓${NC}"
  echo ""
  echo "Next steps:"
  echo "  1. kubectl port-forward svc/falco-falcosidekick-ui -n falco 2802:2802"
  echo "     then open http://localhost:2802 — confirm >=3 named alerts visible"
  echo "  2. make demo-2   (with Falco logs tailing) to confirm zero alerts in normal ops"
  echo "  3. wsl -d rancher-desktop cat /var/log/falco/events.log > logs/falco.log"
  exit 0
else
  echo ""
  echo -e "${RED}Phase 5 verification FAILED — ${FAIL} check(s) failed.${NC}"
  exit 1
fi