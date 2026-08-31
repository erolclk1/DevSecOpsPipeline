---
phase: "06"
plan: "02"
subsystem: docs
tags: [documentation, setup-guide, runbooks, trivy, argocd, falco, jenkins]
dependency_graph:
  requires: []
  provides: [docs/setup.md, docs/scenarios.md]
  affects: []
tech_stack:
  added: []
  patterns: [technical-documentation, demo-runbook]
key_files:
  created:
    - docs/setup.md
    - docs/scenarios.md
  modified: []
decisions:
  - "Used exact content from plan specification — no deviations from prescribed structure"
  - "setup.md documents /var/run/docker.sock (Windows/WSL2) vs ~/.rd/docker.sock (macOS) per Phase 4 empirical finding"
  - "scenarios.md documents demo-3 WSL2 log copy-out kubectl exec fallback per Phase 5 artefact"
metrics:
  duration_minutes: 2
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 0
  completed_date: "2026-08-31"
---

# Phase 6 Plan 02: Documentation — Setup Guide and Demo Runbooks Summary

Step-by-step Windows/WSL2 bootstrap guide and three demo runbooks with exact commands, expected outputs, timing notes, and pass/fail criteria for thesis committee demo.

---

## Objective

Write `docs/setup.md` (bootstrap guide) and `docs/scenarios.md` (three demo runbooks) accurate to the empirical Phase 1–4 findings — correct port 5001 throughout, exact commands, troubleshooting for top failure modes.

---

## Tasks Completed

| Task | Name | Status | Commit | Files |
|------|------|--------|--------|-------|
| 1 | Write docs/setup.md — bootstrap guide | Done | fe957c5 | docs/setup.md (200 lines) |
| 2 | Write docs/scenarios.md — three demo runbooks | Done | c7cf9f9 | docs/scenarios.md (208 lines) |

---

## Key Artifacts

### docs/setup.md (200 lines)

- Prerequisites table: Rancher Desktop 1.23.1, 16 GB RAM, Python 3
- Steps 1–10: install RD → clone repo → make up → configure insecure-registries → rdctl restart → verify phase 1 → build app → make stack → verify → pre-warm
- Troubleshooting: registry ImagePullBackOff, Falco CrashLoopBackOff, Jenkins CSRF 403
- Docker socket path: `/var/run/docker.sock` (Windows/WSL2), NOT `~/.rd/docker.sock` (macOS only)
- Resource budget table: ~4.1 GB steady state, 6 GB VM recommended

### docs/scenarios.md (208 lines)

- **Scenario 1:** `make demo-1` — Trivy blocks vulnerable image at SCAN stage, no image pushed
- **Scenario 2:** `make demo-2` — Fixed image passes all 4 stages (BUILD/SCAN/PUSH/BUMP), ArgoCD auto-syncs
- **Scenario 3:** `make demo-3` — Attack scripts trigger Falco alerts (`reverse-shell`, `read-sensitive-file`, `package-management-in-container`)
- Each runbook: prerequisites, exact commands, expected terminal output, timing notes, UI observation steps, pass criteria
- Quick reference table: all 3 scenarios with commands and duration

---

## Verification Results

All acceptance criteria passed:

| Check | Result |
|-------|--------|
| `grep "5001" docs/setup.md` | PASS |
| `grep "insecure-registries" docs/setup.md` | PASS |
| `grep "rdctl shutdown" docs/setup.md` | PASS |
| `grep "make stack" docs/setup.md` | PASS |
| `grep "/var/run/docker.sock" docs/setup.md` | PASS |
| `grep "demo-warmup" docs/setup.md` | PASS |
| `wc -l docs/setup.md` | 200 (>80) PASS |
| `grep "make demo-1" docs/scenarios.md` | PASS |
| `grep "make demo-2" docs/scenarios.md` | PASS |
| `grep "make demo-3" docs/scenarios.md` | PASS |
| `grep "make demo-warmup" docs/scenarios.md` | PASS |
| `grep "5001" docs/scenarios.md` | PASS |
| `grep "read-sensitive-file" docs/scenarios.md` | PASS |
| `grep "2802" docs/scenarios.md` | PASS |
| `wc -l docs/scenarios.md` | 208 (>100) PASS |

---

## Deviations from Plan

None — plan executed exactly as written. Both files contain precisely the content specified in the plan's action blocks.

---

## Known Stubs

None — all commands, ports, hostnames, and Falco rule names in both files are accurate to the empirical findings from Phases 1–5. No placeholder values remain.

---

## Self-Check: PASSED

Files exist:
- docs/setup.md: FOUND
- docs/scenarios.md: FOUND

Commits exist:
- fe957c5: FOUND (docs(06-02): add docs/setup.md — bootstrap guide for Windows/WSL2)
- c7cf9f9: FOUND (docs(06-02): add docs/scenarios.md — three demo runbooks)
