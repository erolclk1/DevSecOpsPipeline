#!/usr/bin/env bash
# cluster/setup.sh — Bootstrap Phase 1: local registry + insecure-registry config
#
# PREREQUISITE (one-time, manual):
#   Install Rancher Desktop 1.23.1, container engine = dockerd (moby),
#   enable Kubernetes, set Memory to 6 GB, wait for "Kubernetes: Running".
#
# ROOT CAUSE THIS SCRIPT FIXES:
#   Rancher Desktop with the dockerd (moby) engine runs k3s via cri-dockerd,
#   so image pulls go through the DOCKER DAEMON — NOT containerd.
#   => /etc/rancher/k3s/registries.yaml is IGNORED with the dockerd engine.
#   => The Docker daemon inside the VM must have insecure-registries set,
#      otherwise it tries HTTPS against our plain-HTTP registry and fails with
#      "http: server gave HTTP response to HTTPS client".
#
# Run from Git Bash (Windows) or Terminal (macOS):
#   bash cluster/setup.sh

REGISTRY_PORT="5001"
REGISTRY_REF="host.rancher-desktop.internal:${REGISTRY_PORT}"
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

# ── 2. Start registry:2 on port 5001 ─────────────────────────────────────────
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
  || die "Registry not reachable at localhost:${REGISTRY_PORT} — check: docker ps"

# ── 3. Install RD provisioning script for insecure-registries ────────────────
# A manually-written /etc/docker/daemon.json is OVERWRITTEN by Rancher Desktop
# on restart. A provisioning script re-applies the config on EVERY boot, before
# dockerd starts — this is the reliable, restart-proof approach.
echo "── Installing insecure-registry provisioning script ────────────────────"
bash "${SCRIPT_DIR}/install-provisioning.sh" \
  || warn "Provisioning install reported an issue — see output above."

# ── 4. Restart Rancher Desktop to run the provisioning script ────────────────
echo ""
warn "Rancher Desktop must be restarted so the provisioning script runs."
echo "  Option A (CLI): rdctl shutdown && rdctl start"
echo "  Option B (GUI): Rancher Desktop tray icon → Quit, then reopen"
echo ""
echo "After restart, verify the daemon picked up the config:"
echo "  docker info | grep -A2 'Insecure Registries'"
echo "  (should list ${REGISTRY_REF})"
echo ""
echo "Then run: bash cluster/verify.sh"
echo "── Setup complete ───────────────────────────────────────────────────────"
