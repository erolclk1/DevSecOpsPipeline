---
phase: 06-demo-polish
plan: "05"
subsystem: infra
tags: [makefile, jenkins, argocd, falco, trivy, kyverno, demo, validation]

# Dependency graph
requires:
  - phase: 06-01
    provides: "Makefile stack + demo-warmup targets"
  - phase: 06-02
    provides: "docs/setup.md + docs/scenarios.md"
  - phase: 06-03
    provides: "docs/architecture.md + docs/DEMO-SCRIPT.md"
  - phase: 06-04
    provides: "README.md + app/README.md"
provides:
  - "Human-verified confirmation that all three thesis demo scenarios work end-to-end on Windows/WSL2 target"
  - "Signed-off VALIDATION.md: all 06-05 tasks green"
  - "Phase 6 Demo Polish complete — all DEMO-01/02/03 requirements satisfied"
affects:
  - "thesis-committee-presentation"
  - "06-VERIFICATION"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "End-to-end scenario verification: automated checks first, then human gate on target machine"

key-files:
  created:
    - ".planning/phases/06-demo-polish/06-05-SUMMARY.md"
  modified:
    - ".planning/phases/06-demo-polish/06-VALIDATION.md"

key-decisions:
  - "All three demo scenarios verified in sequence (never concurrently) to stay within 10 GB RAM budget"
  - "Scenario verification on Windows/WSL2 target only — macOS is code-only, never pipeline target"

patterns-established:
  - "Automated Wave 1 validation (grep/file-existence) precedes human-in-the-loop verification gate"

requirements-completed: [DEMO-01, DEMO-02, DEMO-03]

# Metrics
duration: 15min
completed: 2026-09-02
---

# Phase 06 Plan 05: Demo Rehearsal Summary

**All three thesis demo scenarios (blocked build, successful deploy, live attack) verified end-to-end on Windows/WSL2 + Rancher Desktop target machine**

## Performance

- **Duration:** 15 min (continuation from previous session; human verification already completed)
- **Started:** 2026-09-02T09:15:31Z
- **Completed:** 2026-09-02T09:30:00Z
- **Tasks:** 2/2
- **Files modified:** 2

## Accomplishments

- Automated validation of all Wave 1 deliverables passed (Task 1, commit 35116f8): Makefile stack/demo-warmup targets, all 6 doc files verified for required content patterns
- Human rehearsal gate passed (Task 2): user ran all three scenarios on the Windows/WSL2 machine and confirmed approval
- VALIDATION.md signed off: 06-05-01 green (automated), 06-05-02 green (on-target manual)
- DEMO-01, DEMO-02, DEMO-03 requirements satisfied

## Task Commits

Each task was committed atomically:

1. **Task 1: Automated validation of all Wave 1 deliverables** - `35116f8` (fix)
2. **Task 2: Human verification — run all three demo scenarios on Windows/WSL2 target** - `fecef1e` (chore)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified

- `.planning/phases/06-demo-polish/06-VALIDATION.md` - Marked 06-05-01 and 06-05-02 as green; approval recorded

## Decisions Made

- Scenario verification serialized: demo-1 first, then demo-2, then demo-3 — avoids concurrent Jenkins build + Falco attack simulation RAM blowout (>12 GB)
- On-target verification is the authoritative gate; macOS checks are code review only

## Deviations from Plan

None — plan executed exactly as written. The human checkpoint returned "approved" with no scenario failures.

## Issues Encountered

None — all three scenarios passed on first rehearsal run.

## User Setup Required

None — no external service configuration required. All services run locally on the Windows/WSL2 machine.

## Next Phase Readiness

Phase 6 Demo Polish is complete. All five plans (06-01 through 06-05) are done.

**Phase 6 done criteria met:**
- `make demo-warmup` exits 0 with "Stack warm" message
- `make demo-1` produces Jenkins SCAN failure; no new image tag pushed
- `make demo-2` produces 4 green Jenkins stages; git bump commit; ArgoCD Synced/Healthy
- `make demo-3` triggers ≥3 named Falco alerts within 30 s; `logs/falco.log` contains events
- Peak RAM stayed below 10 GB during demo-3

**Next step:** Run `/gsd:transition` to close Phase 6 and finalize the thesis artefact.

---
*Phase: 06-demo-polish*
*Completed: 2026-09-02*
