#!/usr/bin/env bash
# ci/tests/scenario-2.sh — Phase 4: SUCCESSFUL deploy assertion (CI-04, CI-05).
# Proves that the fixed image (app/Dockerfile.fixed, node:22-alpine) passes SCAN,
# gets pushed to the registry under the git SHA tag, and that the pipeline bumps
# deploy/overlays/local/demoapp-patch.yaml in Git (which ArgoCD then syncs).
# Exits non-zero unless the build SUCCEEDED, the tag is present, and Git is bumped.
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
PATCH="deploy/overlays/local/demoapp-patch.yaml"

# ── Guard: admin creds required ───────────────────────────────────────────────
if [ -z "${JENKINS_ADMIN_USER:-}" ] || [ -z "${JENKINS_ADMIN_PASSWORD:-}" ]; then
  echo "JENKINS_ADMIN_USER / JENKINS_ADMIN_PASSWORD not set."
  echo "Source the Jenkins admin creds first, e.g.:  source ci/.env"
  exit 2
fi

AUTH="${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}"
SHA=$(git rev-parse --short HEAD)

echo "── Scenario 2: fixed build must DEPLOY (tag + manifest bump) ───────────"
echo "current git SHA: ${SHA}"

# ── 1. Trigger the fixed build (DOCKERFILE=Dockerfile.fixed) ──────────────────
curl -sf -X POST -u "$AUTH" \
  "${JENKINS}/job/${JOB}/buildWithParameters?DOCKERFILE=Dockerfile.fixed" \
  || die "could not trigger ${JOB} build (is Jenkins up and the job seeded?)"
ok "triggered fixed build"

# ── 2. Poll lastBuild until it has a result (timeout 10 min) ──────────────────
RESULT=""
for i in $(seq 1 120); do
  RESULT=$(curl -sf -u "$AUTH" "${JENKINS}/job/${JOB}/lastBuild/api/json" 2>/dev/null \
    | sed -n 's/.*"result":"\([A-Z]*\)".*/\1/p')
  [ -n "$RESULT" ] && [ "$RESULT" != "null" ] && break
  sleep 5
done
[ -n "$RESULT" ] || die "build did not finish within 10 min (no result)"
echo "build result: ${RESULT}"

[ "$RESULT" = "SUCCESS" ] \
  || die "expected build result SUCCESS, got '${RESULT}' — fixed image did not deploy"
ok "build succeeded"

# ── 3. Assert the SHA tag is present in the registry ──────────────────────────
curl -sf "$REGISTRY_TAGS" | grep -q "$SHA" \
  || die "registry has no tag ${SHA} — PUSH stage did not run"
ok "registry has tag ${SHA}"

# ── 4. Assert the manifest was bumped in Git (origin/main) ────────────────────
git fetch origin main >/dev/null 2>&1 || warn "git fetch origin main failed — checking local ref"
if git log origin/main -1 --format='%s' -- "$PATCH" 2>/dev/null | grep -q "$SHA" \
   || git show "origin/main:${PATCH}" 2>/dev/null | grep -q "demoapp:$SHA"; then
  ok "${PATCH} bumped to demoapp:${SHA} in Git"
else
  die "${PATCH} was not bumped to demoapp:${SHA} on origin/main — BUMP stage did not commit"
fi

ok "Scenario 2: fixed build deployed, tag+bump present"
echo -e "${GREEN}✓ Scenario 2: fixed build deployed, tag+bump present${NC}"
exit 0
