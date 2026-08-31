---
phase: "06"
plan: "03"
subsystem: docs
tags: [documentation, architecture, demo-script, thesis]
dependency_graph:
  requires: []
  provides: [docs/architecture.md, docs/DEMO-SCRIPT.md]
  affects: [thesis-defence, committee-presentation]
tech_stack:
  added: []
  patterns: [Mermaid-flowchart, ASCII-art-diagrams]
key_files:
  created:
    - docs/architecture.md
    - docs/DEMO-SCRIPT.md
  modified: []
decisions:
  - "Mermaid flowchart LR chosen for GitHub-renderable component diagram"
  - "Demo script includes Bulgarian narration for each scenario to support thesis defence"
  - "Fallback procedures added for three most common failure modes (Jenkins agent, port-forward, ArgoCD sync)"
metrics:
  duration: "~2 minutes"
  completed: "2026-08-31"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 0
requirements_met:
  - DOCS-03
---

# Phase 06 Plan 03: Architecture Diagram and Demo Script Summary

**One-liner:** Mermaid component diagram with three security layers plus line-by-line thesis committee demo script with Bulgarian narration and fallback procedures.

---

## What Was Built

### Task 1 — docs/architecture.md (commit: 91f607e)

Created `docs/architecture.md` with:
- `flowchart LR` Mermaid diagram showing all five named components (Jenkins, ArgoCD, Kyverno, Falco, Registry) with data flow edges
- Red-styled "blocked" nodes for Trivy exit-1 and Kyverno policy-deny paths
- ASCII art data flow diagram from git push through Jenkins → registry → ArgoCD → Kyverno → cluster → Falco
- ASCII art network topology diagram showing host / Rancher Desktop VM / k3s cluster namespace boundaries
- Key design decisions table (modern_ebpf driver, port 5001, JCasC, GitOps rule, Kyverno over Rego)

File: 140 lines. All acceptance criteria passed.

### Task 2 — docs/DEMO-SCRIPT.md (commit: ccfb789)

Created `docs/DEMO-SCRIPT.md` with:
- Pre-demo checklist referencing `make demo-warmup` and browser tab setup
- Three scenario scripts with exact commands, wait times, and what to point at in the UI
- Bulgarian + English dual narration for each scenario (committee-friendly)
- Pass/fail checks for each scenario
- Fallback procedures for Jenkins agent timeout, Falcosidekick port-forward drop, ArgoCD sync failure
- Expected committee Q&A in Bulgarian and English

File: 170 lines. All acceptance criteria passed.

---

## Deviations from Plan

None - plan executed exactly as written.

---

## Known Stubs

None. Both files contain complete, wired content — no placeholder text or TODO items.

---

## Self-Check: PASSED

Files exist:
- FOUND: docs/architecture.md (140 lines, Mermaid flowchart present, all 5 components named)
- FOUND: docs/DEMO-SCRIPT.md (170 lines, make demo-warmup present, fallback procedures present)

Commits exist:
- FOUND: 91f607e — docs(06-03): add architecture.md with Mermaid component diagram
- FOUND: ccfb789 — docs(06-03): add DEMO-SCRIPT.md — thesis committee presentation script
