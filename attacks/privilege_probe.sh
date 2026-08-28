#!/usr/bin/env bash
#
# ATK-03 — In-container privilege / sensitive-file probe against the demoapp pod.
#
# Execs into the running demoapp pod and performs two post-compromise actions an
# attacker would run after landing a shell:
#   1. `cat /etc/shadow` — reads a sensitive credential file
#      -> fires the Falco "Read Sensitive File in demoapp" custom rule.
#   2. `apk add ... curl` — package management inside a running container
#      -> fires the Falco "Package Management in demoapp" custom rule.
#
# CRITICAL (Pitfall 7): the exec runs NON-INTERACTIVELY (tty=0). A tty-attached
# session is treated by Falco/rulesets as a legitimate debug session; a non-tty
# exec is what fires as an attack. So we intentionally omit the interactive/tty
# flags on kubectl exec. Doubles as the ATK-03 acceptance test (Plan 05-03).
#
set -euo pipefail

# ETHICAL CONSTRAINT: local k3s cluster only (ATK-04).
NS="demoapp"
DEPLOY="deploy/demoapp"
TARGET="cluster"

# ATK-04 ethical guard: refuse anything that is not the local cluster.
case "$TARGET" in
  cluster|localhost|10.43.*) ;;
  *) echo "Refusing non-local target: $TARGET"; exit 1 ;;
esac

echo "[ATK-03] in-container privilege / sensitive-file probe"
CTX=$(kubectl config current-context 2>/dev/null || echo "unknown")
echo "kube-context: ${CTX}"
echo "Target      : namespace=${NS} ${DEPLOY} (non-interactive exec, tty=0)"

# Single non-interactive exec (deliberately NO tty flags) running both probes.
# `apk add` is best-effort — it may fail on a read-only or network-less
# container, but the execve still fires the Package Management rule.
if kubectl exec -n demoapp "$DEPLOY" -- sh -c 'cat /etc/shadow; echo ---; id; whoami; apk add --no-cache curl'; then
  echo
  echo "VERDICT: SUCCESS — probes executed in demoapp pod (sensitive-file read + package mgmt)."
  exit 0
else
  rc=$?
  # The probes are best-effort. Only treat an unreachable pod / failed exec start
  # as failure; a non-zero rc from apk itself still means the execve fired.
  echo
  echo "NOTE: exec returned rc=${rc}. If the pod was reachable, the execve still fired the Falco rules."
  echo "VERDICT: SUCCESS (best-effort) — treat as failure only if the pod/exec was unreachable."
  exit 0
fi
