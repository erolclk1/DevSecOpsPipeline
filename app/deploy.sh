#!/usr/bin/env bash
# app/deploy.sh — Phase 2: update Kustomize overlay tag + kubectl apply
#
# PREREQUISITE: app/build.sh ran successfully (.env.phase2 exists)
#
# Run from Git Bash (Windows) or Terminal (macOS):
#   bash app/deploy.sh

REGISTRY_HOST="host.rancher-desktop.internal"
REGISTRY_PORT="5001"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PATCH_FILE="${REPO_ROOT}/deploy/overlays/local/demoapp-patch.yaml"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*"; exit 1; }

echo "── DevSecOps Pipeline — Phase 2: Deploy ────────────────────────────────"

# ── 1. Load TAG ───────────────────────────────────────────────────────────────
ENV_FILE="${REPO_ROOT}/.env.phase2"
if [ -f "${ENV_FILE}" ]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  ok "Loaded TAG=${TAG} from .env.phase2"
else
  TAG=$(git rev-parse --short HEAD 2>/dev/null) \
    || die "No .env.phase2 found and not a git repo — run app/build.sh first"
  warn "No .env.phase2 found — using current HEAD: TAG=${TAG}"
fi

IMAGE="${REGISTRY_HOST}:${REGISTRY_PORT}/demoapp:${TAG}"

# ── 2. Pre-flight ─────────────────────────────────────────────────────────────
kubectl get nodes --no-headers 2>/dev/null | grep -q "Ready" \
  || die "k3s not Ready. Start Rancher Desktop."
ok "k3s cluster Ready"

# Confirm the image was pushed
curl -sf "http://localhost:${REGISTRY_PORT}/v2/demoapp/tags/list" 2>/dev/null | grep -q "${TAG}" \
  || die "Image tag ${TAG} not found in registry. Run app/build.sh first."
ok "Image ${TAG} confirmed in registry"

# ── 3. Patch demoapp-patch.yaml with the real TAG ─────────────────────────────
echo "── Updating deploy/overlays/local/demoapp-patch.yaml ───────────────────"
# Use sed to replace any image line that contains /demoapp: — works without yq
sed -i.bak "s|image: ${REGISTRY_HOST}:${REGISTRY_PORT}/demoapp:.*|image: ${IMAGE}|" "${PATCH_FILE}" \
  && rm -f "${PATCH_FILE}.bak"
ok "Patched demoapp-patch.yaml → ${IMAGE}"

# ── 4. Deploy ─────────────────────────────────────────────────────────────────
echo "── Applying manifests ───────────────────────────────────────────────────"
kubectl apply -k "${REPO_ROOT}/deploy/overlays/local/" \
  || die "kubectl apply failed"
ok "Manifests applied"

echo "── Waiting for rollout ──────────────────────────────────────────────────"
kubectl rollout status deployment/demoapp -n demoapp --timeout=120s \
  || die "Rollout timed out — check: kubectl describe pod -n demoapp"
ok "Deployment rolled out"

echo ""
echo "── Deploy complete ──────────────────────────────────────────────────────"
echo "  Next: make verify-phase-2"
