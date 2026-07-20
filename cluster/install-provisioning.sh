#!/usr/bin/env bash
# cluster/install-provisioning.sh — Install the RD provisioning script (Windows)
#
# Copies cluster/insecure-registry.start into Rancher Desktop's provisioning
# directory so dockerd trusts our HTTP registry on EVERY start (survives restarts).
#
# Run from Git Bash on Windows:
#   bash cluster/install-provisioning.sh
#
# Then restart Rancher Desktop: rdctl shutdown && rdctl start

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/insecure-registry.start"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*"; exit 1; }

echo "── Installing RD provisioning script ───────────────────────────────────"

[ -f "${SRC}" ] || die "Source not found: ${SRC}"

# Resolve %LOCALAPPDATA% from Git Bash on Windows
if [ -n "${LOCALAPPDATA:-}" ]; then
  # Convert Windows path (C:\Users\..\AppData\Local) to a Git Bash path
  PROV_DIR=$(cygpath -u "${LOCALAPPDATA}" 2>/dev/null)/rancher-desktop/provisioning
else
  # Fallback: construct from USERPROFILE
  PROV_DIR=$(cygpath -u "${USERPROFILE}" 2>/dev/null)/AppData/Local/rancher-desktop/provisioning
fi

[ -n "${PROV_DIR}" ] || die "Could not resolve %LOCALAPPDATA%. Are you running in Git Bash on Windows?"

mkdir -p "${PROV_DIR}" || die "Could not create ${PROV_DIR}"
DEST="${PROV_DIR}/insecure-registry.start"

# Copy and FORCE Unix line endings (RD provisioning scripts break with CRLF)
tr -d '\r' < "${SRC}" > "${DEST}" || die "Copy failed"
chmod +x "${DEST}" 2>/dev/null || true

ok "Installed: ${DEST}"

# Verify line endings are LF (no CR)
if grep -q $'\r' "${DEST}" 2>/dev/null; then
  warn "CRLF detected in ${DEST} — provisioning scripts require LF. Re-check."
else
  ok "Line endings are LF (correct)"
fi

echo ""
echo "Next:"
echo "  1. Restart Rancher Desktop:  rdctl shutdown && rdctl start"
echo "  2. Verify daemon picked it up:  docker info | grep -A2 'Insecure Registries'"
echo "     (should list host.rancher-desktop.internal:5001)"
echo "  3. Run:  bash cluster/verify.sh"
echo "── Done ─────────────────────────────────────────────────────────────────"
