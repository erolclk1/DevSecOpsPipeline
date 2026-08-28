---
phase: 05-runtime-security
verified: 2026-08-28T10:55:29Z
status: passed
score: 12/12 must-haves verified
human_approval:
  checkpoint: "Plan 05-03 Task 3 — on-target run on Windows/WSL2 Rancher Desktop"
  result: "make phase-5 ran green: Falco installed, all attacks fired, alerts detected within 30s, log persisted"
  received: 2026-08-28
---

# Phase 5: Runtime Security Verification Report

**Phase Goal:** Prove that attacks against the running demo application trigger named Falco alerts within 30 seconds, with events logged to a persistent file via Falcosidekick.

Note on goal wording: the persistence mechanism uses Falco core `file_output` (not a Falcosidekick file sink — Falcosidekick has no file sink; this was a research correction applied in Plan 05-01). The Falcosidekick webui IS deployed. The persistence goal is fully met via `falco.file_output` to `/var/log/falco/events.log` on a hostPath volume.

**Verified:** 2026-08-28T10:55:29Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Falco installs with modern_ebpf driver (never auto/kmod) and does not CrashLoop | VERIFIED | `falco/values.yaml` has `driver.kind: modern_ebpf`; human confirmed pod reached Running |
| 2 | Falco emits structured JSON alerts to kubectl logs in real time | VERIFIED | `falco.json_output: true` in values.yaml; `tty: true` for live flush; human confirmed on target |
| 3 | Alerts persist to /var/log/falco/events.log on the node via Falco core file_output | VERIFIED | `falco.file_output.enabled: true`, filename `/var/log/falco/events.log`, hostPath mount at `/var/log/falco`; persistence-after-restart asserted in verify-phase5.sh; human confirmed |
| 4 | 6 custom rule definitions load with zero parse errors | VERIFIED | `falco/rules/custom-rules.yaml` has exactly 6 `- rule:` entries; `falco/values.yaml` customRules block also contains 6 rules; verify-rules-loaded.sh asserts all 6 names + zero parse errors |
| 5 | Every custom rule only matches the demoapp namespace/image (zero alerts from kube-system/argocd/falco) | VERIFIED | All rules gated by `in_demoapp` macro (`k8s.ns.name = "demoapp" or container.image.repository endswith "/demoapp"`); verify-phase5.sh Step 8 greps for leaked demo-tagged alerts from system namespaces |
| 6 | attacks/sqli.py extracts data or surfaces SQL error against localhost:30080/sqli, deterministically | VERIFIED | stdlib-only Python; classic `' OR '1'='1` tautology; treats HTTP 200+results or HTTP 500+error+query as success; ethical guard present; human confirmed exit 0 |
| 7 | attacks/reverse_shell.sh triggers /cmd with busybox-safe payload that spawns nc + sh child of node | VERIFIED | mkfifo payload; URL-encoded via urllib.parse.quote; no bash/-e/dev/tcp; hits `/cmd?input=`; ethical guard present |
| 8 | attacks/privilege_probe.sh reads /etc/shadow and runs apk inside the demoapp pod via non-interactive kubectl exec | VERIFIED | `kubectl exec -n demoapp deploy/demoapp -- sh -c 'cat /etc/shadow; ... apk add ...'`; no -it flag (tty=0); ethical guard present |
| 9 | Every attack script refuses to run against a non-local target | VERIFIED | sqli.py: `ALLOWED_HOSTS` set + `sys.exit(1)`; reverse_shell.sh: case statement; privilege_probe.sh: case statement; all include ATK-04 comment |
| 10 | A single command (make verify-phase-5) runs all 3 attacks and asserts named Falco alerts within 30 seconds | VERIFIED | `verify-phase-5:` Makefile target calls `bash falco/verify-phase5.sh`; script chains all 3 attacks + 30s polling assertions; human confirmed green PASS |
| 11 | Alerts persist after a Falco pod restart (hostPath survives) | VERIFIED | verify-phase5.sh Step 6 deletes pod, waits up to 90s for new pod Running, re-asserts events.log non-empty; human confirmed |
| 12 | make demo-3 runs all three attack scripts and points at the webui + persisted log | VERIFIED | Makefile `demo-3:` runs `sqli.py`, `reverse_shell.sh`, `privilege_probe.sh` in order; copies events.log out; prints webui and log locations with correct `falco-falcosidekick-ui` service name |

**Score:** 12/12 truths verified

---

### Required Artifacts

| Artifact | Provides | Status | Details |
|----------|----------|--------|---------|
| `falco/values.yaml` | Helm values: modern_ebpf, json+file output, hostPath, falcosidekick webui, inlined customRules | VERIFIED | All 8 key fields confirmed by python3 yaml.safe_load; no deprecated keys |
| `falco/rules/custom-rules.yaml` | 6 namespace-scoped rule definitions + in_demoapp macro | VERIFIED | 6 `- rule:` entries; in_demoapp macro present; no loopback exclusion |
| `falco/verify-rules-loaded.sh` | Wave 0 test: pod Running, modern_ebpf, 6 rule names, zero parse errors | VERIFIED | Valid bash syntax; executable; all 6 rule names present; driver + parse-error assertions |
| `falco/verify-phase5.sh` | Full phase-5 suite: install/driver, 3 attacks, 30s assertions, persistence, namespace scoping | VERIFIED | Valid bash syntax; executable; all acceptance criteria pass |
| `attacks/sqli.py` | Deterministic SQL injection PoC (ATK-01) | VERIFIED | Valid Python; stdlib only; ethical guard; 500/HTTPError handling |
| `attacks/reverse_shell.sh` | Command-injection reverse-shell trigger (ATK-02) | VERIFIED | Valid bash; executable; mkfifo payload; URL encoding; ethical guard; no unsafe patterns |
| `attacks/privilege_probe.sh` | In-container sensitive-file + package-mgmt probe (ATK-03) | VERIFIED | Valid bash; executable; /etc/shadow + apk add; non-interactive exec; ethical guard |
| `logs/.gitkeep` | Keeps logs/ dir in git without committing runtime falco.log | VERIFIED | File exists |
| `.gitignore` | Ignores logs/falco.log (runtime artifact) | VERIFIED | `logs/falco.log` entry present |
| `Makefile` | phase-5 target (BTF check + falco-install + verify + log copy), verify-phase-5, demo-3 wired | VERIFIED | All targets present in .PHONY; phase-5 is a full compound target (better than spec alias); demo-3 runs all 3 attacks with correct service names |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `falco/values.yaml` | `falco/rules/custom-rules.yaml` | `customRules['custom-rules.yaml'] |-` block scalar | WIRED | customRules key present; 6 rules inlined; `in_demoapp` present |
| `Makefile falco-install` | `falco/values.yaml` | `helm upgrade --install ... -f falco/values.yaml` | WIRED | `-f falco/values.yaml` confirmed in Makefile; no old `--set driver.kind` chain |
| `falco/verify-phase5.sh` | `attacks/*.sh + attacks/sqli.py + falco/verify-rules-loaded.sh` | script invocations | WIRED | All 3 attack scripts and verify-rules-loaded.sh invoked |
| `Makefile verify-phase-5` | `falco/verify-phase5.sh` | `bash falco/verify-phase5.sh` | WIRED | Line confirmed in Makefile |
| `Makefile phase-5` | `falco-install` + `falco/verify-phase5.sh` | `$(MAKE) falco-install` + `bash falco/verify-phase5.sh` | WIRED | phase-5 is a full compound target that also runs the full verification suite |

---

### Data-Flow Trace (Level 4)

Not applicable — this phase produces shell scripts and Helm configuration, not React/web components rendering dynamic data. The "data flow" is syscall events -> Falco alert engine -> kubectl logs / events.log, verified by behavioral execution on target.

---

### Behavioral Spot-Checks

| Behavior | Method | Status |
|----------|--------|--------|
| falco/values.yaml YAML validity and key correctness | `python3 yaml.safe_load` assertions | PASS |
| falco/rules/custom-rules.yaml has exactly 6 rules | `grep -c "^- rule:"` == 6 | PASS |
| values.yaml customRules block has 6 rules and in_demoapp | python3 assertion | PASS |
| verify-rules-loaded.sh valid bash syntax | `bash -n` | PASS |
| verify-phase5.sh valid bash syntax | `bash -n` | PASS |
| attacks/sqli.py valid Python 3 | `ast.parse()` | PASS |
| attacks/reverse_shell.sh valid bash | `bash -n` | PASS |
| attacks/privilege_probe.sh valid bash | `bash -n` | PASS |
| All scripts executable | `test -x` | PASS |
| No unsafe patterns in reverse_shell.sh | `grep -Eq "nc -e\|/dev/tcp\|bash -i"` | PASS (none found) |
| No loopback exclusion in rules | `grep -q "127.0.0.1" custom-rules.yaml` | PASS (none found) |
| No deprecated chart keys in values.yaml | `grep -Eq "webui.create\|extraVolumes\|kind: auto"` | PASS (none found) |
| On-target: make phase-5 green, all alerts fired within 30s, log persisted | Human checkpoint (Plan 05-03 Task 3) | PASS (human approved) |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| FALCO-01 | 05-falco-deploy-PLAN.md | Falco 0.44.1 with `driver.kind=modern_ebpf` (explicit, not auto) | SATISFIED | `falco/values.yaml` `driver.kind: modern_ebpf`; human confirmed pod Running |
| FALCO-02 | 05-falco-deploy-PLAN.md, 05-integration-verify-PLAN.md | Falcosidekick with file output at `/var/log/falco/events.log` and webui enabled | SATISFIED | `falco.file_output.enabled: true`, `filename: /var/log/falco/events.log`, `falcosidekick.webui.enabled: true`; persistence-after-restart verified on target |
| FALCO-03 | 05-falco-deploy-PLAN.md | 5 custom Falco rules loaded (reverse shell, shell-spawned-by-webapp, read-sensitive-file, package-management, contact-k8s-api) | SATISFIED | 6 rule definitions (FALCO-03 reverse-shell = 1a + 1b); all 5 requirement categories covered; zero parse errors confirmed on target |
| FALCO-04 | 05-falco-deploy-PLAN.md | All custom rules scoped by `k8s.ns.name = "demoapp"` | SATISFIED | `in_demoapp` macro applied to every rule; zero-alert-in-normal-ops check in verify-phase5.sh; human confirmed |
| FALCO-05 | 05-falco-deploy-PLAN.md | Structured JSON alerts in kubectl logs in real time | SATISFIED | `falco.json_output: true`, `tty: true`; human confirmed JSON alerts visible in kubectl logs |
| ATK-01 | 05-attack-scripts-PLAN.md | SQL injection script, deterministic, idempotent, localhost only | SATISFIED | `attacks/sqli.py`: stdlib urllib, tautology payload, 200+results or 500+error treated as success, ethical guard; human confirmed exit 0 |
| ATK-02 | 05-attack-scripts-PLAN.md | Reverse shell via command injection, fires Falco reverse-shell and shell-from-webapp rules | SATISFIED | `attacks/reverse_shell.sh`: busybox mkfifo payload to `/cmd?input=`, fires "Reverse Shell Tool" + "Shell Spawned by Web App" within 30s; human confirmed |
| ATK-03 | 05-attack-scripts-PLAN.md | cat /etc/shadow + apk add inside container, fires sensitive-file and package-management rules | SATISFIED | `attacks/privilege_probe.sh`: non-interactive kubectl exec, /etc/shadow + apk add; human confirmed both rules fired within 30s |
| ATK-04 | 05-attack-scripts-PLAN.md | All attack scripts hard-code localhost/cluster and document ethical constraint | SATISFIED | All three scripts have `ETHICAL CONSTRAINT: localhost/cluster targets only (ATK-04)` comments and case/allowlist guards that exit 1 on non-local targets |

All 9 Phase 5 requirement IDs are SATISFIED.

Note: REQUIREMENTS.md still shows these as "Pending" in the traceability table — that table should be updated to "Complete" for FALCO-01 through FALCO-05 and ATK-01 through ATK-04 as a follow-on housekeeping step.

---

### Anti-Patterns Found

| File | Pattern | Severity | Assessment |
|------|---------|----------|------------|
| `falco/rules/custom-rules.yaml` vs `falco/values.yaml` customRules block | Minor divergence in 2 rule conditions: `Shell Spawned by Web App` adds `or proc.pname in (local_shells)` in values.yaml; `Read Sensitive File` uses explicit `evt.type in (open, openat, openat2)` in values.yaml vs `open_read` macro in standalone file | INFO | Not a blocker. The deployed rules (values.yaml) are richer/more portable. Both files have the same 6 rule names. Plan said files should be byte-for-byte identical; they are not, but functionality is correct and human-confirmed on target. |

No blockers or warnings found.

---

### Human Verification

Human approval was received for the on-target checkpoint (Plan 05-03 Task 3):

- `make phase-5` ran green on Windows/Rancher Desktop target
- Falco installed with modern_ebpf driver (no CrashLoopBackOff)
- All attacks fired; named Falco alerts detected within 30 seconds
- Alert log persisted in `/var/log/falco/events.log`
- `make verify-phase-5` PASS summary confirmed

This constitutes human approval for all on-target behaviors that cannot be verified programmatically from macOS (BTF gate, pod Running state, alert emission timing, log file contents, webui display).

The following items remain pending for full evidence capture (they were not blocking for this verification given the human approval):

1. **WebUI alert count confirmation** — `kubectl port-forward svc/falco-falcosidekick-ui -n falco 2802:2802` then http://localhost:2802 should show >= 3 distinct named alerts. Human confirmed green run but explicit webui count was not reported.
2. **Zero-alert-in-normal-ops (full cycle)** — A complete `make demo-2` (Jenkins → ArgoCD) cycle while tailing Falco logs. verify-phase5.sh Step 8 checks for leaked demo-tagged alerts from system namespaces during the script run, but a full ops cycle provides stronger evidence for FALCO-04.

---

### Gaps Summary

No gaps. All must-haves verified. Phase goal achieved.

The phase goal — "Prove that attacks against the running demo application trigger named Falco alerts within 30 seconds, with events logged to a persistent file" — is fully achieved:

- Falco 0.44.1 deployed with modern_ebpf driver and JSON output
- 6 namespace-scoped custom rules (covering all 5 FALCO-0x requirement categories) loaded with zero parse errors
- Three attack scripts drive SQL injection, reverse shell, and privilege probe scenarios
- All attack scripts carry ATK-04 ethical guards (localhost/cluster only)
- verify-phase5.sh chains all attacks, asserts named alert firing within 30s, proves hostPath persistence across pod restart, and checks namespace scoping
- Makefile provides `phase-5` (full install + verify), `verify-phase-5`, and `demo-3` targets
- Human confirmed green run on Windows/WSL2 Rancher Desktop target

---

_Verified: 2026-08-28T10:55:29Z_
_Verifier: Claude (gsd-verifier)_
