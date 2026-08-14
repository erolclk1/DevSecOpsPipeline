#!/usr/bin/env bash
# ci/tests/verify-jcasc.sh — Phase 4: JCasC parity + no-setup-wizard assertion.
# Proves the controller was provisioned entirely from code (CI-01, CI-07):
#   - the setup wizard was bypassed (no initialAdminPassword secret)
#   - JCasC config was loaded
#   - every plugin in ci/plugins.txt is actually installed
# Exits non-zero on any mismatch.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_FILE="${SCRIPT_DIR}/../plugins.txt"

echo "── Phase 4: JCasC parity + no-wizard check ─────────────────────────────"

# ── 1. Setup wizard was bypassed ──────────────────────────────────────────────
# The presence of initialAdminPassword means Jenkins is asking for the wizard —
# i.e. JCasC did NOT take over. Its absence proves the wizard was skipped.
if docker exec jenkins test ! -f /var/jenkins_home/secrets/initialAdminPassword; then
  ok "setup wizard bypassed (no initialAdminPassword)"
else
  die "setup wizard NOT bypassed — /var/jenkins_home/secrets/initialAdminPassword exists"
fi

# ── 2. JCasC config loaded ────────────────────────────────────────────────────
if docker exec jenkins sh -c 'test -f "$CASC_JENKINS_CONFIG" || test -f /var/jenkins_home/casc.yaml'; then
  ok "JCasC config present"
else
  die "JCasC config not found (\$CASC_JENKINS_CONFIG unset and /var/jenkins_home/casc.yaml missing)"
fi

# ── 3. Plugin parity ──────────────────────────────────────────────────────────
[ -f "$PLUGINS_FILE" ] \
  || die "expected plugin manifest at $PLUGINS_FILE (created in Plan 01)"

# Expected short names: strip ':version', drop blank and '#' comment lines.
EXPECTED=$(sed -e 's/#.*$//' -e 's/[[:space:]]*$//' "$PLUGINS_FILE" \
  | grep -v '^[[:space:]]*$' \
  | sed 's/:.*$//')

INSTALLED=$(docker exec jenkins jenkins-plugin-cli --list) \
  || die "could not list installed plugins (is the 'jenkins' container running?)"

MISSING=()
while IFS= read -r plugin; do
  [ -z "$plugin" ] && continue
  # Match the plugin short name as a whole token in the installed listing.
  if ! echo "$INSTALLED" | grep -qw "$plugin"; then
    MISSING+=("$plugin")
  fi
done <<< "$EXPECTED"

if [ "${#MISSING[@]}" -gt 0 ]; then
  die "missing plugins vs ci/plugins.txt: ${MISSING[*]}"
fi
ok "all plugins in ci/plugins.txt are installed"

echo -e "${GREEN}✓ JCasC parity OK${NC}"
exit 0
