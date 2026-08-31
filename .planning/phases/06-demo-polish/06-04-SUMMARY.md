---
phase: "06"
plan: "04"
subsystem: documentation
tags: [readme, owasp, vulnerability-docs, app-docs]
dependency_graph:
  requires: []
  provides: [README.md, app/README.md]
  affects: [docs/setup.md, docs/scenarios.md]
tech_stack:
  added: []
  patterns: [owasp-2021-citation, ascii-architecture-diagram, vulnerability-documentation]
key_files:
  created:
    - README.md
    - app/README.md
  modified: []
decisions:
  - "Used node:14.21.3-alpine (actual Dockerfile base image) rather than node:14.0.0-alpine from plan template — actual file is authoritative"
  - "Replaced /health endpoint with / (root) in app/README.md endpoints table — server.js has no /health route"
metrics:
  duration: "~5 minutes"
  completed: "2026-08-31T07:47:26Z"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 0
---

# Phase 6 Plan 04: Documentation READMEs Summary

README.md and app/README.md written with full OWASP 2021 citations, exact server.js line references, ASCII architecture diagram, 5-command quickstart, and security warnings.

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Write README.md — project entry point | 66254ad | README.md |
| 2 | Write app/README.md — vulnerability documentation (APP-05) | 3ce77e3 | app/README.md |

---

## What Was Built

### README.md (DOCS-05)
- ASCII architecture diagram showing the full pipeline flow (portability: renders in PDF, terminal, GitHub)
- 5-command quickstart: `git clone` + `make up` + rdctl restart note + `make stack` + `make demo-warmup`
- Demo scenarios table documenting what each of `demo-1`, `demo-2`, `demo-3` proves
- Prerequisites table (Windows/WSL2, Rancher Desktop 1.23.1, RAM, Git, Python 3)
- Stack versions table with all pinned versions (Jenkins 2.555.3, ArgoCD v3.4.4, Trivy v0.72.0, Falco 0.44.1)
- All port references are 5001 (not 5000)
- Repo layout directory tree
- Documentation links table pointing to docs/setup.md, docs/scenarios.md, docs/architecture.md, docs/DEMO-SCRIPT.md, app/README.md
- Thesis context: TU-Sofia, МКПКП, доц. д-р Я. Томов
- Security warning (MUST NOT deploy outside isolated environment)

### app/README.md (APP-05)
- OWASP A03:2021 — SQL Injection: cites server.js line 32 (`const query = "SELECT * FROM users WHERE id = '" + user + "'"`)
- OWASP A03:2021 — OS Command Injection: cites server.js line 47 (`exec(input, { timeout: 5000 }, ...)`)
- OWASP A06:2021 — Vulnerable and Outdated Components: documents `node:14.21.3-alpine` base image
- OWASP A05:2021 — Security Misconfiguration: documents root container (no USER directive)
- Attack scripts table: sqli.py, reverse_shell.sh, privilege_probe.sh with Falco rules per script
- Endpoints table: `/`, `/sqli`, `/cmd`
- INTENTIONALLY VULNERABLE comment line references: line 28 (SQL) and line 43 (cmd)
- Security warning (MUST NOT deploy outside isolated environment)
- OWASP and CWE reference links

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected base image version in app/README.md**
- **Found during:** Task 2
- **Issue:** Plan template specified `node:14.0.0-alpine` but actual `app/Dockerfile` uses `node:14.21.3-alpine`
- **Fix:** Used the actual base image version from the Dockerfile (`node:14.21.3-alpine`)
- **Files modified:** app/README.md
- **Commit:** 3ce77e3

**2. [Rule 1 - Bug] Removed non-existent /health endpoint from app/README.md**
- **Found during:** Task 2
- **Issue:** Plan template included `/health` in the endpoints table but `app/server.js` has no `/health` route
- **Fix:** Used `/` (root) as the status endpoint, which is what the actual server.js provides
- **Files modified:** app/README.md
- **Commit:** 3ce77e3

---

## Known Stubs

None — both README files document actual code and existing infrastructure. No placeholder content.

---

## Self-Check: PASSED

Files exist:
- README.md: FOUND
- app/README.md: FOUND

Commits exist:
- 66254ad (Task 1 — README.md): FOUND
- 3ce77e3 (Task 2 — app/README.md): FOUND
