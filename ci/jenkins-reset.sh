#!/usr/bin/env bash
# ci/jenkins-reset.sh — wipe all Jenkins volumes and reprovision from JCasC (no UI steps).
set -euo pipefail

COMPOSE="ci/docker-compose.yml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*"; exit 1; }

echo "── Jenkins reset — full reprovision from JCasC ──────────────────────────"

# ── 1. Require secrets ──────────────────────────────────────────────────────
if [ ! -f ci/.env ]; then
  warn "copy ci/.env.example to ci/.env and fill GITHUB_TOKEN + admin creds"
  exit 2
fi
ok "ci/.env present"

# ── 2. Tear down + wipe volumes (jenkins_home, trivy_cache, agent_work) ──────
docker compose -f ci/docker-compose.yml down -v
ok "Volumes wiped — clean slate"

# ── 3. Rebuild + start controller + agent ───────────────────────────────────
docker compose -f ci/docker-compose.yml up -d --build
ok "Controller + agent starting"

# ── 4. Wait for the controller login page ───────────────────────────────────
echo "── Waiting for Jenkins controller ───────────────────────────────────────"
for i in $(seq 1 60); do
  if curl -sf -o /dev/null http://localhost:8080/login; then
    ok "Controller responding on :8080"
    break
  fi
  sleep 5
done

echo "Run: bash ci/tests/verify-jcasc.sh to confirm parity"
ok "Jenkins reset — reprovisioned from JCasC"
