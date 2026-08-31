---
phase: "06"
plan: "01"
subsystem: Makefile
tags: [makefile, bootstrap, demo, trivy, argocd]
dependency_graph:
  requires: []
  provides: [stack-target, demo-warmup-target, up-stop-message]
  affects: [Makefile]
tech_stack:
  added: []
  patterns: [make-phony, make-dependency-chain]
key_files:
  created: []
  modified:
    - Makefile
decisions:
  - "up: target body replaced with explicit STOP message and rdctl restart instruction — mandatory RD restart cannot be automated, correct pattern is up (Phase 1 + STOP) then stack (Phases 3-5)"
  - "stack: chains phase-3 phase-3-apply phase-3-kyverno phase-4 phase-5 — covers all post-restart infrastructure in one command"
  - "demo-warmup uses ECR fallback (public.ecr.aws/aquasecurity/trivy-db) for Trivy DB pull — mirrors Phase 4 empirical finding that ECR fallback is reliable"
metrics:
  duration_minutes: 5
  completed_date: "2026-08-31"
  tasks_completed: 2
  tasks_total: 2
  files_changed: 1
---

# Phase 6 Plan 01: Makefile Bootstrap Integration Summary

**One-liner:** Makefile upgraded with explicit RD restart STOP in `up:`, a `stack:` chain target (phases 3-5), and a `demo-warmup:` pre-demo health check that warms the Trivy DB cache.

## What Was Built

Two new Makefile targets and an upgraded `up:` body that make the bootstrap flow explicit and the demo preparation automated:

- `up:` — now prints a clear STOP message with `rdctl shutdown && rdctl start` instructions and directs the operator to `make stack` after restart
- `stack:` — chains `phase-3 phase-3-apply phase-3-kyverno phase-4 phase-5` in one command, bootstrapping the full post-restart infrastructure
- `demo-warmup:` — 3-step pre-demo checker: k3s node readiness, ArgoCD sync status, and Trivy DB pre-warm via `aquasec/trivy:v0.72.0 --download-db-only` with ECR fallback

Both new targets are declared in `.PHONY`.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | dae24f2 | feat(06-01): upgrade up target with STOP message and add stack target |
| Task 2 | f12fbc7 | feat(06-01): add demo-warmup target for pre-demo stack verification |

## Verification Results

- `make --dry-run up` prints STOP message with `rdctl shutdown && rdctl start` and `make stack` instruction
- `make --dry-run stack` shows `bootstrap/argocd/argocd-install.sh` (phase-3 chained)
- `make --dry-run demo-warmup` shows `kubectl get nodes`, ArgoCD sync check, Trivy DB pull
- `.PHONY` continuation line includes `stack demo-warmup`

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all targets wire to real scripts (phase-3/4/5 targets call existing bootstrap scripts; demo-warmup calls live kubectl/docker commands).

## Self-Check: PASSED

- Makefile exists at worktree root: confirmed
- `^stack:` target present: confirmed
- `^demo-warmup:` target present: confirmed
- Commits dae24f2, f12fbc7 exist in git log: confirmed
