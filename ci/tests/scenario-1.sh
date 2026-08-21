#!/usr/bin/env bash
# ci/tests/scenario-1.sh — Phase 4: BLOCKED build assertion (CI-03).
# Proves that a vulnerable image (app/Dockerfile, node:14.21.3-alpine) makes the
# pipeline fail at the SCAN stage and that NO new tag reaches the registry.
# Exits non-zero unless the build FAILED and the registry is unchanged.
set -euo pipefail

# Load Jenkins admin credentials from project ci/.env
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [ -f "${PROJECT_ROOT}/ci/.env" ]; then
  set -a
  source "${PROJECT_ROOT}/ci/.env"
  set +a
fi

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
COOKIE_JAR="$(mktemp)"
trap 'rm -f "${COOKIE_JAR}" /tmp/jenkins-trigger-response' EXIT

CRUMB_JSON=$(curl -sf \
  -c "${COOKIE_JAR}" \
  -u "${AUTH}" \
  "${JENKINS}/crumbIssuer/api/json" \
  || die "could not obtain Jenkins CSRF crumb")

CRUMB_FIELD=$(printf '%s' "${CRUMB_JSON}" \
  | sed -n 's/.*"crumbRequestField":"\([^"]*\)".*/\1/p')

CRUMB=$(printf '%s' "${CRUMB_JSON}" \
  | sed -n 's/.*"crumb":"\([^"]*\)".*/\1/p')

[ -n "${CRUMB_FIELD}" ] \
  || die "could not parse Jenkins crumb field: ${CRUMB_JSON}"

[ -n "${CRUMB}" ] \
  || die "could not parse Jenkins crumb: ${CRUMB_JSON}"

echo "Jenkins crumb field: ${CRUMB_FIELD}"

HTTP_CODE=$(curl -sS \
  -b "${COOKIE_JAR}" \
  -c "${COOKIE_JAR}" \
  -o /tmp/jenkins-trigger-response \
  -w '%{http_code}' \
  -X POST \
  -u "${AUTH}" \
  -H "${CRUMB_FIELD}: ${CRUMB}" \
  --data-urlencode "${CRUMB_FIELD}=${CRUMB}" \
  --data-urlencode "DOCKERFILE=Dockerfile" \
  "${JENKINS}/job/${JOB}/buildWithParameters" \
  || true)

if [ "${HTTP_CODE}" != "201" ] && [ "${HTTP_CODE}" != "200" ]; then
  echo "Jenkins trigger HTTP status: ${HTTP_CODE}"
  echo "Jenkins response:"
  cat /tmp/jenkins-trigger-response
  echo
  echo "Jenkins crumb response:"
  echo "${CRUMB_JSON}"
  echo
  echo "Jenkins cookies:"
  cat "${COOKIE_JAR}"
  die "could not trigger ${JOB} build"
fi

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
