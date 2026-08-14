#!/usr/bin/env bash
# ci/smoke-test.sh — Phase 4: Jenkins + registry health check.
# Exits non-zero on any failure so CI / Make targets can gate on it.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*"; exit 1; }

echo "── Phase 4: smoke test (Jenkins + registry) ────────────────────────────"

# ── 1. Registry reachable ─────────────────────────────────────────────────────
# Push/scan path always uses localhost:5001 (HTTP, no TLS). Manifests use the
# in-VM hostname; that is NOT what we probe from the host here.
curl -sf http://localhost:5001/v2/ | grep -q '{}' \
  || die "registry not reachable at localhost:5001"
ok "registry reachable at localhost:5001"

# ── 2. Jenkins controller up ──────────────────────────────────────────────────
# Poll the login endpoint; a JCasC-provisioned controller returns 200 or 403
# (403 when anonymous read is disabled) — either proves the servlet is serving.
JENKINS_UP=""
for i in $(seq 1 30); do
  CODE=$(curl -sf -o /dev/null -w '%{http_code}' http://localhost:8080/login 2>/dev/null || echo "000")
  if [ "$CODE" = "200" ] || [ "$CODE" = "403" ]; then
    JENKINS_UP="yes"
    break
  fi
  sleep 2
done
[ -n "$JENKINS_UP" ] \
  || die "Jenkins controller not responding at http://localhost:8080 after 60s (HTTP $CODE)"
ok "Jenkins controller up at http://localhost:8080 (HTTP $CODE)"

# ── 3. Agent can reach the docker socket ──────────────────────────────────────
# The agent container (jenkins-agent, per Plan 02 docker-compose) must be able to
# talk to the docker daemon it will build/scan with.
if docker exec jenkins-agent docker info >/dev/null 2>&1; then
  ok "agent docker OK"
else
  die "agent cannot reach docker socket — check /var/run/docker.sock mount (Pitfall 1)"
fi

echo -e "${GREEN}✓ smoke test passed${NC}"
exit 0
