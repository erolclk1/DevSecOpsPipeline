#!/usr/bin/env bash
# cluster/setup.sh — Bootstrap Phase 1: local registry + registries.yaml
#
# PREREQUISITE (one-time, manual):
#   Install Rancher Desktop 1.23.1, enable Kubernetes, set Memory to 6 GB,
#   wait for "Kubernetes: Running" in the UI.
#
# Run from Git Bash (Windows) or Terminal (macOS):
#   bash cluster/setup.sh

REGISTRY_PORT="5000"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*"; exit 1; }

echo "── DevSecOps Pipeline — Phase 1 Setup ──────────────────────────────────"

# ── 1. Pre-flight ─────────────────────────────────────────────────────────────
kubectl get nodes --no-headers 2>/dev/null | grep -q "Ready" \
  || die "Kubernetes not Ready. Start Rancher Desktop and wait for 'Kubernetes: Running'."
ok "k3s cluster is Ready"

docker info &>/dev/null \
  || die "Docker not reachable. Is Rancher Desktop running?"
ok "Docker engine reachable"

# ── 2. Start registry:2 ───────────────────────────────────────────────────────
echo "── Starting local registry ──────────────────────────────────────────────"
if docker ps --format '{{.Names}}' | grep -q '^registry$'; then
  ok "registry:2 already running"
else
  docker rm -f registry 2>/dev/null || true
  docker run -d --restart=always -p "${REGISTRY_PORT}:5000" --name registry registry:2
  ok "registry:2 started on port ${REGISTRY_PORT}"
fi

curl -sf "http://localhost:${REGISTRY_PORT}/v2/" | grep -q '{}' \
  && ok "Registry reachable at localhost:${REGISTRY_PORT}" \
  || die "Registry not reachable — check: docker ps"

# ── 3. Copy registries.yaml ───────────────────────────────────────────────────
echo "── Configuring k3s registry mirror ─────────────────────────────────────"

# registries.yaml destination (same path on macOS and Windows/WSL2)
DEST_DIR="$HOME/.rd/k3s"
mkdir -p "${DEST_DIR}"
cp "${SCRIPT_DIR}/registries.yaml" "${DEST_DIR}/registries.yaml"
ok "Copied cluster/registries.yaml → ${DEST_DIR}/registries.yaml"

echo ""
warn "Rancher Desktop must be restarted to reload the containerd config."
echo "  Option A (CLI): rdctl shutdown && rdctl start"
echo "  Option B (GUI): Rancher Desktop tray icon → Restart"
echo ""
echo "After restart, run: bash cluster/verify.sh"
echo "── Setup complete ───────────────────────────────────────────────────────"
