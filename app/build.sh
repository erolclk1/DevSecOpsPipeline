#!/usr/bin/env bash
# app/build.sh — Phase 2: build + Trivy scan + push demoapp image

HOST_REGISTRY="localhost"
CLUSTER_REGISTRY="host.rancher-desktop.internal"
REGISTRY_PORT="5001"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*"; exit 1; }

echo "── DevSecOps Pipeline — Phase 2: Build + Scan + Push ───────────────────"

# ── 1. Pre-flight ─────────────────────────────────────────────────────────────

docker info &>/dev/null \
  || die "Docker not reachable. Is Rancher Desktop running?"
ok "Docker engine reachable"

curl -sf "http://localhost:${REGISTRY_PORT}/v2/" | grep -q '{}' \
  || die "Registry not reachable at localhost:${REGISTRY_PORT}"
ok "Registry reachable at localhost:${REGISTRY_PORT}"

command -v trivy &>/dev/null \
  || die "trivy not found. Install from https://trivy.dev"
ok "trivy found: $(trivy --version 2>/dev/null | head -1)"

# ── 2. Determine image tag ────────────────────────────────────────────────────

TAG=$(git rev-parse --short HEAD 2>/dev/null) \
  || die "Not a git repository"

PUSH_IMAGE="${HOST_REGISTRY}:${REGISTRY_PORT}/demoapp:${TAG}"
DEPLOY_IMAGE="${CLUSTER_REGISTRY}:${REGISTRY_PORT}/demoapp:${TAG}"

echo "── Image tag: ${TAG} ─────────────────────────────────────────────────────"

# ── 3. Build ──────────────────────────────────────────────────────────────────

echo "── Building image ───────────────────────────────────────────────────────"

docker build -t "${PUSH_IMAGE}" "${SCRIPT_DIR}" \
  || die "docker build failed"

ok "Built ${PUSH_IMAGE}"

# ── 4. Trivy scan ─────────────────────────────────────────────────────────────

echo "── Scanning with Trivy ──────────────────────────────────────────────────"

trivy image \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --no-progress \
  "${PUSH_IMAGE}"

TRIVY_EXIT=$?

if [ "${TRIVY_EXIT}" -eq 0 ]; then
  die "Trivy found 0 CRITICAL CVEs — base image may be wrong or DB is stale."
fi

ok "Trivy found CRITICAL CVEs"

# ── 5. Push ───────────────────────────────────────────────────────────────────

echo "── Pushing to registry ──────────────────────────────────────────────────"

docker push "${PUSH_IMAGE}" \
  || die "docker push failed"

ok "Pushed ${PUSH_IMAGE}"

TAGS=$(curl -sf "http://localhost:${REGISTRY_PORT}/v2/demoapp/tags/list")

echo "Registry tags: ${TAGS}"

# ── 6. Save variables for deploy.sh ───────────────────────────────────────────

cat > "${SCRIPT_DIR}/../.env.phase2" <<EOF
TAG=${TAG}
HOST_IMAGE=${PUSH_IMAGE}
DEPLOY_IMAGE=${DEPLOY_IMAGE}
EOF

ok "Wrote .env.phase2"

echo ""
echo "Host image:    ${PUSH_IMAGE}"
echo "Cluster image: ${DEPLOY_IMAGE}"

echo ""
echo "── Build complete ───────────────────────────────────────────────────────"
echo "Next: bash app/deploy.sh"