#!/usr/bin/env bash
# ci/tests/scenario-2.sh — Phase 4: SUCCESSFUL deploy assertion (CI-04, CI-05).
# Proves that the fixed image (app/Dockerfile.fixed, node:22-alpine) passes SCAN,
# gets pushed to the registry under the git SHA tag, and that the pipeline bumps
# deploy/overlays/local/demoapp-patch.yaml in Git (which ArgoCD then syncs).
# Exits non-zero unless the build SUCCEEDED, the tag is present, and Git is bumped.
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
COOKIE_JAR="$(mktemp)"
RESPONSE_FILE="$(mktemp)"

trap 'rm -f "${COOKIE_JAR}" "${RESPONSE_FILE}"' EXIT

CRUMB_JSON=$(curl -sf \
  -c "${COOKIE_JAR}" \
  -u "$AUTH" \
  "${JENKINS}/crumbIssuer/api/json" \
  || die "could not obtain Jenkins CSRF crumb")

CRUMB_FIELD=$(printf '%s' "${CRUMB_JSON}" \
  | sed -n 's/.*"crumbRequestField":"\([^"]*\)".*/\1/p')

CRUMB=$(printf '%s' "${CRUMB_JSON}" \
  | sed -n 's/.*"crumb":"\([^"]*\)".*/\1/p')

[ -n "${CRUMB_FIELD}" ] \
  || die "could not parse Jenkins crumb field"

[ -n "${CRUMB}" ] \
  || die "could not parse Jenkins crumb"

HTTP_CODE=$(curl -sS \
  -D "${RESPONSE_FILE}" \
  -o /tmp/jenkins-trigger-response \
  -b "${COOKIE_JAR}" \
  -c "${COOKIE_JAR}" \
  -w '%{http_code}' \
  -X POST \
  -u "$AUTH" \
  -H "${CRUMB_FIELD}: ${CRUMB}" \
  --data-urlencode "${CRUMB_FIELD}=${CRUMB}" \
  --data-urlencode "DOCKERFILE=Dockerfile.fixed" \
  "${JENKINS}/job/${JOB}/buildWithParameters" \
  || true)

if [ "${HTTP_CODE}" != "201" ] && [ "${HTTP_CODE}" != "200" ]; then
  echo "Jenkins trigger HTTP status: ${HTTP_CODE}"
  cat /tmp/jenkins-trigger-response
  die "could not trigger ${JOB} build"
fi

QUEUE_URL=$(sed -n 's/^Location: *//Ip' "${RESPONSE_FILE}" | tr -d '\r')

[ -n "${QUEUE_URL}" ] \
  || die "Jenkins did not return a queue URL"

ok "triggered fixed build"
echo "queue item: ${QUEUE_URL}"

# ── Snapshot current Jenkins build number ─────────────────────────────────────
PREVIOUS_BUILD=$(curl -sf -u "$AUTH" \
  "${JENKINS}/job/${JOB}/lastBuild/api/json" \
  | sed -n 's/.*"number":\([0-9]*\).*/\1/p')

[ -n "${PREVIOUS_BUILD}" ] \
  || die "could not determine current Jenkins build number"

echo "previous Jenkins build: ${PREVIOUS_BUILD}"

# ── 2. Wait for OUR queued build to start ─────────────────────────────────────
BUILD_NUMBER=""

for i in $(seq 1 120); do
  QUEUE_JSON=$(curl -sf -u "$AUTH" \
    "${QUEUE_URL}api/json" 2>/dev/null) || true

  BUILD_NUMBER=$(printf '%s' "${QUEUE_JSON}" \
    | sed -n 's/.*"number":\([0-9]*\).*/\1/p')

  if [ -n "${BUILD_NUMBER}" ]; then
    break
  fi

  CANCELLED=$(printf '%s' "${QUEUE_JSON}" \
    | sed -n 's/.*"cancelled":\([^,}]*\).*/\1/p')

  if [ "${CANCELLED}" = "true" ]; then
    die "our Jenkins queue item was cancelled"
  fi

  echo "waiting for our queued build to start..."
  sleep 5
done

[ -n "${BUILD_NUMBER}" ] \
  || die "our Jenkins build did not start within 10 min"

echo "our Jenkins build: ${BUILD_NUMBER}"

# ── 3. Wait for OUR build to finish ───────────────────────────────────────────
RESULT=""

for i in $(seq 1 120); do
  RESULT=$(curl -sf -u "$AUTH" \
    "${JENKINS}/job/${JOB}/${BUILD_NUMBER}/api/json" 2>/dev/null \
    | sed -n 's/.*"result":"\([A-Z]*\)".*/\1/p') || true

  if [ -n "${RESULT}" ] && [ "${RESULT}" != "null" ]; then
    break
  fi

  echo "waiting for build #${BUILD_NUMBER} to finish..."
  sleep 5
done

[ -n "${RESULT}" ] \
  || die "build #${BUILD_NUMBER} did not finish within 10 min"

echo "build #${BUILD_NUMBER} result: ${RESULT}"

[ "${RESULT}" = "SUCCESS" ] \
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
