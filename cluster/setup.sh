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

# ── 3. Configure Docker daemon insecure-registries INSIDE the VM ─────────────
# This is the actual fix. The dockerd that k3s uses must treat our registry
# as insecure (HTTP). daemon.json lives in the rancher-desktop WSL2 distro.
echo "── Configuring Docker daemon insecure-registries ───────────────────────"

DAEMON_JSON=$(cat <<EOF
{
  "insecure-registries": ["${REGISTRY_REF}"]
}
EOF
)

DAEMON_WRITTEN=0

detect_rd_distro() {
  wsl --list --quiet 2>/dev/null | tr -d '\r\0' | grep -i "^rancher-desktop$" | head -1
}

if command -v wsl &>/dev/null; then
  # Windows: write daemon.json into the rancher-desktop WSL distro (runs as root)
  RD_DISTRO=$(detect_rd_distro)
  if [ -z "${RD_DISTRO}" ]; then
    RD_DISTRO="rancher-desktop"
  fi
  if wsl -d "${RD_DISTRO}" -- sh -c 'mkdir -p /etc/docker && cat > /etc/docker/daemon.json' <<< "${DAEMON_JSON}" 2>/dev/null; then
    ok "Wrote /etc/docker/daemon.json in WSL distro '${RD_DISTRO}'"
    DAEMON_WRITTEN=1
  fi
elif command -v rdctl &>/dev/null; then
  # macOS/Linux: write via rdctl shell into the Lima VM
  if rdctl shell sudo sh -c 'mkdir -p /etc/docker && cat > /etc/docker/daemon.json' <<< "${DAEMON_JSON}" 2>/dev/null; then
    ok "Wrote /etc/docker/daemon.json via rdctl shell"
    DAEMON_WRITTEN=1
  fi
fi

if [ "${DAEMON_WRITTEN}" -eq 0 ]; then
  warn "Could not write daemon.json into the VM automatically."
  echo ""
  echo "  Run this manually (Windows Git Bash / PowerShell):"
  echo "    wsl -d rancher-desktop -- sh -c 'mkdir -p /etc/docker && cat > /etc/docker/daemon.json' <<'EOF'"
  echo "    ${DAEMON_JSON}"
  echo "    EOF"
  echo ""
  echo "  Or on macOS/Linux:"
  echo "    rdctl shell sudo sh -c 'mkdir -p /etc/docker && printf ... > /etc/docker/daemon.json'"
  echo ""
fi

# Also drop registries.yaml as a best-effort artefact (only used IF engine=containerd)
mkdir -p "$HOME/.rd/k3s"
cp "${SCRIPT_DIR}/registries.yaml" "$HOME/.rd/k3s/registries.yaml" 2>/dev/null || true

# ── 4. Restart Rancher Desktop to reload the Docker daemon ───────────────────
echo ""
warn "Rancher Desktop must be restarted so dockerd reloads daemon.json."
echo "  Option A (CLI): rdctl shutdown && rdctl start"
echo "  Option B (GUI): Rancher Desktop tray icon → Restart Kubernetes / Quit + reopen"
echo ""
echo "After restart, verify the daemon picked up the config:"
echo "  docker info | grep -A2 'Insecure Registries'"
echo "  (should list ${REGISTRY_REF})"
echo ""
echo "Then run: bash cluster/verify.sh"
echo "── Setup complete ───────────────────────────────────────────────────────"
