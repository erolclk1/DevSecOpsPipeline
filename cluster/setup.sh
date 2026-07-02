#!/usr/bin/env bash
# cluster/setup.sh — Bootstrap script for the DevSecOps pipeline
# Run AFTER Rancher Desktop 1.23.1 is installed and Kubernetes is Running.
# Usage: bash cluster/setup.sh

set -euo pipefail

REGISTRY_NAME="registry"
REGISTRY_PORT="5000"
REGISTRIES_YAML="$HOME/.rd/k3s/registries.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*"; exit 1; }

# ── 1. Pre-flight checks ──────────────────────────────────────────────────────
echo "── Pre-flight checks ────────────────────────────────────────────────────"

# Rancher Desktop context
if ! kubectl config current-context 2>/dev/null | grep -q "rancher-desktop"; then
  warn "kubectl context is not 'rancher-desktop'. Switching..."
  docker context use rancher-desktop 2>/dev/null || true
fi

kubectl get nodes --no-headers 2>/dev/null | grep -q "Ready" \
  || die "k3s cluster not Ready. Start Rancher Desktop and wait for 'Kubernetes: Running'."
ok "k3s cluster is Ready"

docker info --context rancher-desktop &>/dev/null \
  || die "Docker (Rancher Desktop) not reachable. Is Rancher Desktop running?"
ok "Docker engine reachable"

# ── 2. Local registry ─────────────────────────────────────────────────────────
echo "── Local registry ───────────────────────────────────────────────────────"

if docker ps --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
  ok "registry:2 already running"
else
  if docker ps -a --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
    warn "Removing stopped registry container..."
    docker rm -f "${REGISTRY_NAME}"
  fi
  docker run -d --restart=always \
    -p "${REGISTRY_PORT}:5000" \
    --name "${REGISTRY_NAME}" \
    registry:2
  ok "registry:2 started on port ${REGISTRY_PORT}"
fi

# Verify host-side reachability
curl -sf "http://localhost:${REGISTRY_PORT}/v2/" | grep -q '{}' \
  || die "Registry not reachable at localhost:${REGISTRY_PORT}"
ok "Registry reachable from host at localhost:${REGISTRY_PORT}"

# ── 3. registries.yaml for k3s containerd ────────────────────────────────────
echo "── k3s registry mirror config ───────────────────────────────────────────"

mkdir -p "$(dirname "${REGISTRIES_YAML}")"
cp "${SCRIPT_DIR}/registries.yaml" "${REGISTRIES_YAML}"
ok "Copied cluster/registries.yaml → ${REGISTRIES_YAML}"

echo ""
warn "Rancher Desktop must be restarted to reload containerd config."
echo "  Run:  rdctl shutdown && rdctl start"
echo "  Then: bash cluster/verify.sh"
echo ""
echo "── Setup complete ───────────────────────────────────────────────────────"
