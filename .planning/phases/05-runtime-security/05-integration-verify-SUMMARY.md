---
phase: 05-runtime-security
plan: 03
status: checkpoint-pending
checkpoint: Task 3 — human-run verification on Windows/WSL2 Rancher Desktop target
completed_tasks: [1, 2]
pending_tasks: [3]
authored_on: 2026-08-28
---

# 05-03 Integration Verify — Summary (Checkpoint Pending)

## What was built

Tasks 1 and 2 completed; Task 3 is a human-verify checkpoint that must run on the
Windows/WSL2 Rancher Desktop target.

### Task 1 — Logs plumbing + Makefile wiring

| Artifact | Description |
|----------|-------------|
| `logs/.gitkeep` | Tracks the `logs/` directory in git without committing runtime logs |
| `.gitignore` | Added `logs/falco.log` (WSL2 copy-out, runtime artifact) |
| `Makefile demo-3` | Rewired: runs all 3 attacks in order (`sqli.py` → `reverse_shell.sh` → `privilege_probe.sh`), copies `events.log` out of the rancher-desktop WSL2 distro, and points at the correct release-prefixed service `falco-falcosidekick-ui` |
| `Makefile verify-phase-5` | New target: `bash falco/verify-phase5.sh` |
| `Makefile .PHONY` | Added `verify-phase-5` |

### Task 2 — falco/verify-phase5.sh

Full end-to-end phase-5 acceptance suite. Runs on the Windows/WSL2 target after
`make phase-5`. Steps in order:

1. **FALCO-01/03**: calls `falco/verify-rules-loaded.sh` — pod Running, `modern_ebpf`,
   all 6 rule definitions loaded, zero parse errors. Suite aborts if this fails.
2. **FALCO-02**: asserts `falco-falcosidekick-ui` service exists in namespace `falco`.
3. **ATK-01**: runs `attacks/sqli.py`, asserts exit 0.
   _No Falco alert is expected — SQL injection executes inside the Node.js process
   with no detectable syscall/spawn._
4. **ATK-02**: runs `attacks/reverse_shell.sh`, then asserts "Shell Spawned by Web App
   in demoapp" AND "Reverse Shell Tool in demoapp" fire within 30 seconds each.
5. **ATK-03**: runs `attacks/privilege_probe.sh`, then asserts "Read Sensitive File
   in demoapp" AND "Package Management in demoapp" fire within 30 seconds each.
6. **Persistence (FALCO-02)**: asserts `events.log` is non-empty, deletes the Falco
   pod, waits up to 90s for the new pod to reach Running, re-asserts `events.log`
   still exists and is non-empty (proves hostPath survives a pod restart).
7. Re-runs `verify-rules-loaded.sh` after the pod restart.
8. **FALCO-04 scoping**: greps the last 600s of Falco logs for demo-tagged alerts from
   `kube-system`, `argocd`, `falco`, or `kube-public` — requires zero matches.
   _(A full `make demo-2` cycle should be run separately for complete evidence of
   success criterion 6.)_

Script exits non-zero if any assertion fails. PASS/FAIL counter printed at end.

## Automated verification (macOS authoring checks — all pass)

```
test -f logs/.gitkeep                                     ✓
grep -q "logs/falco.log" .gitignore                       ✓
grep -q "^verify-phase-5:" Makefile                       ✓
grep -q "python3 attacks/sqli.py" Makefile                ✓
grep -q "attacks/reverse_shell.sh" Makefile               ✓
grep -q "attacks/privilege_probe.sh" Makefile             ✓
grep -q "wsl -d rancher-desktop cat /var/log/falco/events.log" Makefile  ✓
grep -q "falco-falcosidekick-ui" Makefile                 ✓
bash -n falco/verify-phase5.sh                            ✓  (syntax clean)
test -x falco/verify-phase5.sh                            ✓
grep -q "verify-rules-loaded.sh" falco/verify-phase5.sh   ✓
grep -q "attacks/sqli.py" falco/verify-phase5.sh          ✓
grep -q "attacks/reverse_shell.sh" falco/verify-phase5.sh ✓
grep -q "attacks/privilege_probe.sh" falco/verify-phase5.sh ✓
grep -q "Shell Spawned by Web App in demoapp" ...         ✓
grep -q "Reverse Shell Tool in demoapp" ...               ✓
grep -q "Read Sensitive File in demoapp" ...              ✓
grep -q "Package Management in demoapp" ...               ✓
grep -Eq "30|within" falco/verify-phase5.sh               ✓
grep -q "delete pod" falco/verify-phase5.sh               ✓
grep -q "/var/log/falco/events.log" falco/verify-phase5.sh ✓
grep -Eq "kube-system|argocd" falco/verify-phase5.sh      ✓
grep -q "falco-falcosidekick-ui" falco/verify-phase5.sh   ✓
```

## Checkpoint — Task 3 (PENDING)

**Status: awaiting human-run verification on Windows/WSL2 Rancher Desktop target**

This task has no code changes. The operator must run the following on the target
(all steps are automated by the scripts above):

1. **BTF gate**: `wsl -d rancher-desktop ls -l /sys/kernel/btf/vmlinux` and
   `wsl -d rancher-desktop uname -r` (kernel >= 5.8). If missing: `wsl --update`,
   restart Rancher Desktop.
2. **ClusterIP check**: `kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}'`
   — if NOT `10.43.0.1`, update `falco/rules/custom-rules.yaml` and the `customRules`
   block in `falco/values.yaml` with the actual IP.
3. **Install**: `make phase-5` — wait for pod Running.
4. **Rules check**: `bash falco/verify-rules-loaded.sh` — expect exit 0.
5. **Full suite**: `make verify-phase-5` — expect green PASS summary.
6. **WebUI**: `kubectl port-forward svc/falco-falcosidekick-ui -n falco 2802:2802`
   then http://localhost:2802 — confirm >= 3 distinct named alerts.
7. **Log copy-out**: `wsl -d rancher-desktop cat /var/log/falco/events.log > logs/falco.log`
   then `tail -20 logs/falco.log` — confirm JSON alert lines.
8. **Zero-alert ops**: run `make demo-2` while tailing Falco logs — confirm zero demo alerts.

**Resume signal**: type "approved" with the verify-phase-5 PASS/FAIL summary +
webui alert count, or describe failures (BTF missing, rule that did not fire, ClusterIP mismatch).

## Requirements covered

| Req ID | Status | Evidence |
|--------|--------|----------|
| FALCO-01 | Pending target run | verify-rules-loaded.sh checks pod + modern_ebpf |
| FALCO-02 | Pending target run | events.log persistence + webui service asserted |
| FALCO-03 | Pending target run | 6 rule names asserted in logs |
| FALCO-04 | Pending target run | Zero demo alerts from system namespaces |
| FALCO-05 | Pending target run | JSON output + tty flush (structural) |
| ATK-01 | Pending target run | sqli.py exit 0 asserted |
| ATK-02 | Pending target run | 2 Falco alerts within 30s |
| ATK-03 | Pending target run | 2 Falco alerts within 30s |

## Commits

- `424af6c` feat(05-03): add logs plumbing + Makefile verify-phase-5 + demo-3 rewire
- `43ef7bc` feat(05-03): add falco/verify-phase5.sh — full phase-5 verification suite
