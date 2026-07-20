#!/usr/bin/env bash
# cluster/setup.sh — Bootstrap Phase 1: local registry + registries.yaml
#
# PREREQUISITE (one-time, manual):
#   Install Rancher Desktop 1.23.1, enable Kubernetes, set Memory to 6 GB,
#   wait for "Kubernetes: Running" in the UI.
#
# Run from Git Bash (Windows) or Terminal (macOS):
#   bash cluster/setup.sh

REGISTRY_PORT="5001"
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
# Port 5001: Rancher Desktop occupies port 5000 internally.
# Push always via localhost:5001 (plain HTTP, no HTTPS config needed on host).
# k3s pulls via host.rancher-desktop.internal:5001 (configured via registries.yaml below).
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

# ── 3. Write registries.yaml into the Rancher Desktop VM ─────────────────────
# On Windows, ~/.rd/k3s/registries.yaml is NOT read by k3s containerd.
# The file must be written to /etc/rancher/k3s/registries.yaml INSIDE the WSL2 VM.
echo "── Configuring k3s registry mirror ─────────────────────────────────────"

REGISTRIES_CONTENT=$(cat "${SCRIPT_DIR}/registries.yaml")

write_via_wsl() {
  # Find the Rancher Desktop WSL2 distro name (usually "rancher-desktop")
  local distro
  distro=$(wsl --list --quiet 2>/dev/null | tr -d '\r\0' | grep -i "rancher-desktop" | head -1)
  if [ -z "${distro}" ]; then
    return 1
  fi
  wsl -d "${distro}" -- sh -c \
    'mkdir -p /etc/rancher/k3s && cat > /etc/rancher/k3s/registries.yaml' \
    <<< "${REGISTRIES_CONTENT}" 2>/dev/null
  return $?
}

write_via_rdctl() {
  # rdctl shell runs a command inside the Rancher Desktop VM
  rdctl shell -- sh -c \
    'mkdir -p /etc/rancher/k3s && cat > /etc/rancher/k3s/registries.yaml' \
    <<< "${REGISTRIES_CONTENT}" 2>/dev/null
  return $?
}

WRITTEN=0

if command -v wsl &>/dev/null; then
  if write_via_wsl; then
    ok "Written to Rancher Desktop VM via wsl: /etc/rancher/k3s/registries.yaml"
    WRITTEN=1
  fi
fi

if [ "${WRITTEN}" -eq 0 ] && command -v rdctl &>/dev/null; then
  if write_via_rdctl; then
    ok "Written to Rancher Desktop VM via rdctl: /etc/rancher/k3s/registries.yaml"
    WRITTEN=1
  fi
fi

if [ "${WRITTEN}" -eq 0 ]; then
  # Fallback: write to ~/.rd/k3s/ (works on macOS, may work on some Windows setups)
  mkdir -p "$HOME/.rd/k3s"
  cp "${SCRIPT_DIR}/registries.yaml" "$HOME/.rd/k3s/registries.yaml"
  warn "Could not write into VM directly. Wrote to ~/.rd/k3s/registries.yaml (fallback)."
  warn "If SC3/SC4 fail, run manually:"
  echo "  wsl -d rancher-desktop -- sh -c 'mkdir -p /etc/rancher/k3s'"
  echo "  wsl -d rancher-desktop -- sh -c 'cat > /etc/rancher/k3s/registries.yaml' < cluster/registries.yaml"
fi

# ── 4. Restart Rancher Desktop to reload containerd ──────────────────────────
echo ""
warn "Rancher Desktop must be restarted to reload the containerd config."
echo "  Option A (CLI): rdctl shutdown && rdctl start"
echo "  Option B (GUI): Rancher Desktop tray icon → Restart"
echo ""
echo "After restart, run: bash cluster/verify.sh"
echo "── Setup complete ───────────────────────────────────────────────────────"
