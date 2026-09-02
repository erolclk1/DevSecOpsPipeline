---
phase: 6
slug: demo-polish
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-31
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash / grep (docs phase — no test framework) |
| **Config file** | none |
| **Quick run command** | `grep -r "5001" docs/ README.md 2>/dev/null \| wc -l` |
| **Full suite command** | `make --dry-run stack && make --dry-run demo-warmup && bash -n docs/setup.md 2>/dev/null \|\| true` |
| **Estimated runtime** | ~5 seconds (all checks are grep/file-existence) |

---

## Sampling Rate

- **After every task commit:** Run file-existence + grep checks for that task's deliverable
- **After every plan wave:** Run full content spot-checks across all new files
- **Before `/gsd:verify-work`:** All grep checks must pass; 06-05 human checkpoint must be approved
- **Max feedback latency:** 5 seconds (grep-only, no cluster required)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 06-01-01 | makefile | 1 | INFRA-04 | grep | `grep -q "^stack:" Makefile && grep -q "^demo-warmup:" Makefile` | ❌ W0 | ⬜ pending |
| 06-01-02 | makefile | 1 | DOCS-04 | grep | `grep -q "demo-warmup" Makefile && grep -q "PHONY.*demo-warmup\|demo-warmup.*PHONY" Makefile` | ❌ W0 | ⬜ pending |
| 06-02-01 | docs | 1 | DOCS-01 | file+grep | `test -f docs/setup.md && grep -q "5001" docs/setup.md && grep -q "make stack" docs/setup.md` | ❌ W0 | ⬜ pending |
| 06-02-02 | docs | 1 | DOCS-02 | file+grep | `test -f docs/scenarios.md && grep -q "demo-1\|demo-2\|demo-3" docs/scenarios.md` | ❌ W0 | ⬜ pending |
| 06-03-01 | arch | 1 | DOCS-03 | file+grep | `test -f docs/architecture.md && grep -q "mermaid\|graph\|flowchart" docs/architecture.md` | ❌ W0 | ⬜ pending |
| 06-03-02 | arch | 1 | DOCS-03 | file+grep | `test -f docs/DEMO-SCRIPT.md && grep -q "make demo-" docs/DEMO-SCRIPT.md` | ❌ W0 | ⬜ pending |
| 06-04-01 | readme | 1 | DOCS-05 | file+grep | `test -f README.md && grep -q "make phase-5\|make stack\|DevSecOps" README.md` | ❌ W0 | ⬜ pending |
| 06-04-02 | readme | 1 | APP-05 | file+grep | `test -f app/README.md && grep -qi "OWASP\|injection\|vulnerable" app/README.md` | ❌ W0 | ⬜ pending |
| 06-05-01 | verify | 2 | DEMO-01, DEMO-02, DEMO-03 | automated | `grep -q "demo-1" Makefile && grep -q "demo-2" Makefile && grep -q "demo-3" Makefile` | N/A | ✅ green (commit 35116f8) |
| 06-05-02 | verify | 2 | DEMO-01, DEMO-02, DEMO-03 | manual | On-target demo rehearsal checkpoint (see Manual-Only section) | N/A | ✅ green (approved 2026-09-02 on Windows/WSL2) |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `docs/` directory — Wave 1 plans 06-02/03/04 create it
- [ ] `docs/setup.md` — Wave 1 Plan 06-02
- [ ] `docs/scenarios.md` — Wave 1 Plan 06-02
- [ ] `docs/architecture.md` — Wave 1 Plan 06-03
- [ ] `docs/DEMO-SCRIPT.md` — Wave 1 Plan 06-03
- [ ] `README.md` — Wave 1 Plan 06-04
- [ ] `app/README.md` — Wave 1 Plan 06-04
- [ ] `Makefile` stack + demo-warmup targets — Wave 1 Plan 06-01

*All files created during Wave 1 execution — no pre-existing infrastructure needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `make demo-1` blocks vulnerable image and exits | DEMO-01 | Requires Jenkins + cluster running | Run `make demo-1`; expect SCAN stage FAILED in Jenkins console |
| `make demo-2` deploys fixed image via ArgoCD | DEMO-02 | Requires Jenkins + ArgoCD running | Run `make demo-2`; confirm ArgoCD syncs new SHA |
| `make demo-3` triggers Falco alerts | DEMO-03 | Requires Falco + demoapp running | Run `make demo-3`; confirm alerts in Falcosidekick webui |
| Full stack reproduces in ≤60 min from docs | INFRA-04 | Cannot automate RD restart step | Follow `docs/setup.md` start-to-finish; time the process |
| `docs/setup.md` instructions are complete and correct | DOCS-01 | Human judgment on clarity | Read through setup.md on a fresh machine or mentally trace each step |

---

## INFRA-04 Accepted Deviation

**ROADMAP SC-1** states "`make up` provisions the full stack and exits 0." This is technically inaccurate: Rancher Desktop requires a manual restart after `make up` (Phase 1 registry setup) before `make stack` (phases 3–5) can run. The two-step process `make up` → restart → `make stack` is the correct documented approach. This deviation is accepted and documented in `docs/setup.md`. INFRA-04 is considered satisfied when the full stack reproduces in under 60 minutes following `docs/setup.md`.

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Wave 1 plans each own non-overlapping file sets (verified: Makefile / docs/ / README.md / app/README.md)
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s for all automated checks
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** SIGNED OFF — all three demo scenarios verified on Windows/WSL2 target, 2026-09-02
