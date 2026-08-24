---
phase: 5
slug: runtime-security
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-24
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash / shell (no test framework — infra/config phase) |
| **Config file** | none — verification scripts created in Wave 1 |
| **Quick run command** | `bash -n falco/rules/custom-rules.yaml 2>/dev/null \|\| yq '.' falco/rules/custom-rules.yaml > /dev/null` |
| **Full suite command** | `bash falco/verify-phase5.sh` (on-target Windows/WSL2 only) |
| **Estimated runtime** | ~120 seconds (on-target); ~5 seconds (syntax checks on macOS) |

---

## Sampling Rate

- **After every task commit:** Run syntax/structure checks (grep, bash -n, python3 -c "import ast") — macOS-compatible, no cluster required
- **After every plan wave:** Run `bash falco/verify-rules-loaded.sh` (requires Falco on target) + `bash attacks/verify-phase5.sh` (full end-to-end, target only)
- **Before `/gsd:verify-work`:** Full suite must be green on Windows/Rancher Desktop target
- **Max feedback latency:** 30 seconds (Falco alert detection window per phase goal)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-01 | falco-deploy | 1 | FALCO-01, FALCO-02, FALCO-05 | file-check | `test -f falco/values.yaml && grep -q 'modern_ebpf' falco/values.yaml` | ❌ W0 | ⬜ pending |
| 05-01-02 | falco-deploy | 1 | FALCO-03, FALCO-04 | syntax+count | `python3 -c "import yaml,sys; d=yaml.safe_load(open('falco/rules/custom-rules.yaml')); assert sum(1 for r in d if r.get('rule')) == 6"` | ❌ W0 | ⬜ pending |
| 05-01-03 | falco-deploy | 1 | FALCO-01, FALCO-03 | script-syntax | `bash -n falco/verify-rules-loaded.sh` | ❌ W0 | ⬜ pending |
| 05-02-01 | attack-scripts | 1 | ATK-01, ATK-04 | syntax+guard | `python3 -c "import ast; ast.parse(open('attacks/sqli.py').read())"` | ❌ W0 | ⬜ pending |
| 05-02-02 | attack-scripts | 1 | ATK-02, ATK-04 | syntax+guard | `bash -n attacks/reverse_shell.sh && grep -qi 'ATK-04\|ETHICAL\|Refusing non-local' attacks/reverse_shell.sh` | ❌ W0 | ⬜ pending |
| 05-02-03 | attack-scripts | 1 | ATK-03, ATK-04 | syntax+guard | `bash -n attacks/privilege_probe.sh && grep -qi 'ATK-04\|ETHICAL\|Refusing non-local' attacks/privilege_probe.sh` | ❌ W0 | ⬜ pending |
| 05-03-01 | integration-verify | 2 | FALCO-02, FALCO-04, FALCO-05 | script-syntax | `bash -n falco/verify-phase5.sh` | ❌ W0 | ⬜ pending |
| 05-03-02 | integration-verify | 2 | FALCO-01, ATK-01, ATK-02, ATK-03 | grep-check | `grep -q 'verify-phase-5\|verify-phase5' Makefile` | ❌ W0 | ⬜ pending |
| 05-03-03 | integration-verify | 2 | ALL | manual | On-target checkpoint (see Manual-Only section) | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `falco/rules/custom-rules.yaml` — 6-rule YAML, Wave 1 Plan 01 creates it
- [ ] `falco/values.yaml` — Helm values file, Wave 1 Plan 01 creates it
- [ ] `falco/verify-rules-loaded.sh` — rule load verifier, Wave 1 Plan 01 creates it
- [ ] `attacks/sqli.py` — Wave 1 Plan 02 creates it
- [ ] `attacks/reverse_shell.sh` — Wave 1 Plan 02 creates it
- [ ] `attacks/privilege_probe.sh` — Wave 1 Plan 02 creates it
- [ ] `falco/verify-phase5.sh` — Wave 2 Plan 03 creates it
- [ ] `logs/.gitkeep` — ensures `logs/` directory is tracked by git

*All files are created during Wave 1/2 execution — no pre-existing infrastructure needed for macOS authoring tasks.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Falco pod Running + modern_ebpf driver | FALCO-01 | Requires cluster on Windows/WSL2 | `kubectl get pods -n falco`; logs show "driver: modern_ebpf" and "Falco initialized" |
| All 6 rules load without parse errors | FALCO-03 | Requires Falco DaemonSet running | `bash falco/verify-rules-loaded.sh` (on-target) |
| Reverse-shell attack triggers alerts in ≤30s | ATK-02, FALCO-02 | Requires live cluster + listener | Run `attacks/reverse_shell.sh`; check Falcosidekick webui + falco.log |
| Privilege probe triggers read-sensitive + pkg-mgmt alerts | ATK-03, FALCO-02 | Requires live cluster | Run `attacks/privilege_probe.sh`; check alerts |
| `logs/falco.log` persists after pod restart | FALCO-02 | Requires live cluster | Delete Falco pod, verify log file retained on host |
| Zero alerts during ArgoCD/Jenkins normal ops | FALCO-04 | Requires full pipeline run | Run `make demo-1`; monitor `kubectl logs -f <falco-pod> -n falco` for zero alerts |
| BTF vmlinux exists pre-install | FALCO-01 | WSL2-only environment check | `wsl -d rancher-desktop -- test -f /sys/kernel/btf/vmlinux && echo OK` (must run before helm install) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s (for on-target checks)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
