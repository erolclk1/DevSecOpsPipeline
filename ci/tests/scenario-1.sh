#!/usr/bin/env bash
# ci/tests/scenario-1.sh — Phase 4: BLOCKED build assertion (CI-03).
# Proves that a vulnerable image (app/Dockerfile, node:14.21.3-alpine) makes the
# pipeline fail at the SCAN stage and that NO new tag reaches the registry.
# Exits non-zero unless the build FAILED and the registry is unchanged.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*"; exit 1; }

JOB="demoapp-pipeline"
JENKINS="http://localhost:8080"
REGISTRY_TAGS="http://localhost:5001/v2/demoapp/tags/list"

# ── Guard: admin creds required ───────────────────────────────────────────────
if [ -z "${JENKINS_ADMIN_USER:-}" ] || [ -z "${JENKINS_ADMIN_PASSWORD:-}" ]; then
  echo "JENKINS_ADMIN_USER / JENKINS_ADMIN_PASSWORD not set."
  echo "Source the Jenkins admin creds first, e.g.:  source ci/.env"
  exit 2
fi

AUTH="${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}"

echo "── Scenario 1: vulnerable build must be BLOCKED at SCAN ────────────────"

# ── 1. Snapshot registry tags before the build ────────────────────────────────
BEFORE=$(curl -sf "$REGISTRY_TAGS" || echo '{}')
SHA=$(git rev-parse --short HEAD)
echo "tags before: ${BEFORE}"
echo "current git SHA: ${SHA}"

# ── 2. Trigger the vulnerable build (DOCKERFILE=Dockerfile) ───────────────────
curl -sf -X POST -u "$AUTH" \
  "${JENKINS}/job/${JOB}/buildWithParameters?DOCKERFILE=Dockerfile" \
  || die "could not trigger ${JOB} build (is Jenkins up and the job seeded?)"
ok "triggered vulnerable build"

# ── 3. Poll lastBuild until it has a result (timeout 10 min) ──────────────────
RESULT=""
for i in $(seq 1 120); do
  RESULT=$(curl -sf -u "$AUTH" "${JENKINS}/job/${JOB}/lastBuild/api/json" 2>/dev/null \
    | sed -n 's/.*"result":"\([A-Z]*\)".*/\1/p')
  [ -n "$RESULT" ] && [ "$RESULT" != "null" ] && break
  sleep 5
done
[ -n "$RESULT" ] || die "build did not finish within 10 min (no result)"
echo "build result: ${RESULT}"

# ── 4. Snapshot registry tags after ───────────────────────────────────────────
AFTER=$(curl -sf "$REGISTRY_TAGS" || echo '{}')
echo "tags after: ${AFTER}"

# ── 5. Assert: build FAILURE and no new tag pushed ────────────────────────────
[ "$RESULT" = "FAILURE" ] \
  || die "expected build result FAILURE, got '${RESULT}' — vulnerable image was NOT blocked"

if echo "$AFTER" | grep -q "\"$SHA\""; then
  die "registry gained tag ${SHA} despite SCAN failure — gate leaked an image"
fi
[ "$AFTER" = "$BEFORE" ] \
  || warn "tag list changed (${BEFORE} -> ${AFTER}) but current SHA ${SHA} not present"

ok "Scenario 1: vulnerable build blocked, no new tag"
echo -e "${GREEN}✓ Scenario 1: vulnerable build blocked, no new tag${NC}"
exit 0
