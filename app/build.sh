#!/usr/bin/env bash
# app/build.sh — Phase 2: build + Trivy scan + push demoapp image
#
# PREREQUISITE: Phase 1 complete (registry running, registries.yaml configured)
#
# Run from Git Bash (Windows) or Terminal (macOS):
#   bash app/build.sh

REGISTRY_HOST="host.rancher-desktop.internal"
REGISTRY_PORT="5001"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*"; exit 1; }

echo "── DevSecOps Pipeline — Phase 2: Build + Scan + Push ───────────────────"

# ── 1. Pre-flight ─────────────────────────────────────────────────────────────
docker info &>/dev/null || die "Docker not reachable. Is Rancher Desktop running?"
ok "Docker engine reachable"

curl -sf "http://localhost:${REGISTRY_PORT}/v2/" | grep -q '{}' \
  || die "Registry not reachable at localhost:${REGISTRY_PORT}. Run: make phase-1"
ok "Registry reachable at localhost:${REGISTRY_PORT}"

command -v trivy &>/dev/null || die "trivy not found. Install from https://trivy.dev"
ok "trivy found: $(trivy --version 2>/dev/null | head -1)"

# ── 2. Determine image tag ────────────────────────────────────────────────────
TAG=$(git rev-parse --short HEAD 2>/dev/null) \
  || die "Not a git repository — run from the project root"
IMAGE="${REGISTRY_HOST}:${REGISTRY_PORT}/demoapp:${TAG}"
echo "── Image tag: ${TAG} ─────────────────────────────────────────────────────"

# ── 3. Build ──────────────────────────────────────────────────────────────────
echo "── Building image ───────────────────────────────────────────────────────"
docker build -t "${IMAGE}" "${SCRIPT_DIR}" \
  || die "docker build failed"
ok "Built ${IMAGE}"

# ── 4. Trivy scan — must find CRITICAL CVEs ───────────────────────────────────
echo "── Scanning with Trivy ──────────────────────────────────────────────────"
trivy image --severity HIGH,CRITICAL --exit-code 1 --no-progress "${IMAGE}"
TRIVY_EXIT=$?

if [ "${TRIVY_EXIT}" -eq 0 ]; then
  die "Trivy found 0 CRITICAL CVEs — base image may be wrong or DB is stale. Run: trivy image --download-db-only"
fi
ok "Trivy found CRITICAL CVEs (exit ${TRIVY_EXIT}) — vulnerable base image confirmed"

# ── 5. Push ───────────────────────────────────────────────────────────────────
echo "── Pushing to registry ──────────────────────────────────────────────────"
docker push "${IMAGE}" || die "docker push failed"
ok "Pushed ${IMAGE}"

TAGS=$(curl -sf "http://localhost:${REGISTRY_PORT}/v2/demoapp/tags/list" 2>/dev/null)
echo "  Registry tags: ${TAGS}"

# ── 6. Write TAG to .env.phase2 for deploy.sh ─────────────────────────────────
echo "TAG=${TAG}" > "${SCRIPT_DIR}/../.env.phase2"
ok "Wrote .env.phase2 with TAG=${TAG}"

echo ""
echo "── Build complete ───────────────────────────────────────────────────────"
echo "  Next: bash app/deploy.sh   OR   make phase-2-deploy"
