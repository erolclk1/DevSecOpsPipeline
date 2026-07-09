---
phase: 2
plan: "02-01"
subsystem: app
tags: [vulnerable-app, node.js, dockerfile, sqli, cmdi, trivy]
dependency_graph:
  requires: [01-02]
  provides: [app/server.js, app/Dockerfile, app/package-lock.json]
  affects: [02-02]
tech_stack:
  added: [express@4.18.2, mysql@2.18.1, node:14.21.3-alpine]
  patterns: [deliberate-vulnerability, pinned-base-image, root-container]
key_files:
  created:
    - app/server.js
    - app/package.json
    - app/package-lock.json
    - app/Dockerfile
    - app/.dockerignore
    - .gitignore
  modified: []
decisions:
  - "Used node:14.21.3-alpine as base image (EOL April 2023, carries CRITICAL CVEs in OpenSSL/expat/zlib)"
  - "Used mysql@2.18.1 (not mysql2) to make parameterised query bypass harder to stumble into"
  - "Used Option A (local npm install via Node.js 24.4.1) — Node.js available on dev machine"
  - "No USER directive — container runs as root (uid 0) for Kyverno admission violation demo in Phase 3"
metrics:
  duration: "< 5 minutes"
  completed: "2026-07-09"
  tasks_completed: 3
  files_created: 6
---

# Phase 2 Plan 01: Vulnerable App Scaffold Summary

**One-liner:** Deliberately vulnerable Node.js REST API with SQLi + CMDi endpoints using node:14.21.3-alpine base to guarantee Trivy CRITICAL findings.

---

## Artefact Confirmation

All three required artefacts exist and are committed:

| File | Status | Key Property |
|------|--------|-------------|
| `app/server.js` | Created + committed | `// INTENTIONALLY VULNERABLE` markers on SQL concat line and exec call |
| `app/Dockerfile` | Created + committed | `FROM node:14.21.3-alpine`, no USER directive |
| `app/.dockerignore` | Created + committed | Contains `node_modules` and `.git` |
| `app/package.json` | Created + committed | `express@4.18.2`, `mysql@2.18.1` |
| `app/package-lock.json` | Generated + committed | npm install via Node.js 24.4.1 (Option A) |
| `.gitignore` | Created + committed | `node_modules/` excluded from repo |

---

## Base Image

```
FROM node:14.21.3-alpine
```

Node.js 14 reached End of Life April 2023. This version carries known HIGH/CRITICAL CVEs in OpenSSL, expat, zlib, and Node.js itself (V8, libuv). Trivy scan on the Windows target machine (Plan 02-02) will confirm at least one CRITICAL finding.

---

## Git Commit

**Commit SHA:** `fa10776`
**Message:** `feat(02-vulnerable-app): scaffold vulnerable Node.js API with SQLi and CMDi endpoints`

Files committed:
- `.gitignore`
- `app/.dockerignore`
- `app/Dockerfile`
- `app/package-lock.json`
- `app/package.json`
- `app/server.js`

---

## Must_haves Verification

- [x] `app/server.js` contains `// INTENTIONALLY VULNERABLE` on SQL concatenation line (line 31)
- [x] `app/server.js` contains `// INTENTIONALLY VULNERABLE` on exec call (line 46)
- [x] `app/Dockerfile` starts with `FROM node:14.21.3-alpine`
- [x] `app/Dockerfile` has NO `USER` directive
- [x] `app/.dockerignore` contains `node_modules`
- [x] `app/.dockerignore` contains `.git`
- [x] `app/package-lock.json` exists
- [x] All files committed to git

---

## Deviations from Plan

**Option A used for npm install (not Option B):** Node.js 24.4.1 was available locally on the macOS dev machine (`/opt/homebrew/bin/node`), so `npm install` ran directly without Docker. The generated `package-lock.json` is functionally equivalent to what Option B would produce — it locks the same dependency tree.

**Root `.gitignore` created:** The plan referenced adding `node_modules/` to the existing `.gitignore`, but no `.gitignore` existed in the repo. A new one was created with `node_modules/` as the sole entry. This is a minor required addition (Rule 2: missing critical functionality), not a plan deviation.

No other deviations.

---

## Known Stubs

None. All endpoints are fully wired:
- `/sqli` executes real SQL (DB error surfaced to caller is the proof of exploitability)
- `/cmd` executes real shell commands via `child_process.exec`
- `/` health probe returns `{ status: 'ok' }`

---

## Next Plan

**02-02:** Build, push to registry, write Kustomize manifests, deploy to k3s cluster, run acceptance tests (Windows target machine).

## Self-Check: PASSED

- `app/server.js` — FOUND
- `app/Dockerfile` — FOUND
- `app/.dockerignore` — FOUND
- `app/package-lock.json` — FOUND
- Commit `fa10776` — FOUND in git log
