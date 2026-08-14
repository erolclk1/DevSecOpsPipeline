---
phase: 04-jenkins-ci
plan: 04-test-scaffolds
subsystem: ci-validation
tags: [ci, testing, trivy, gitops, jenkins, scaffolds]
dependency-graph:
  requires:
    - "app/Dockerfile (vulnerable node:14.21.3-alpine base — Scenario 1 input)"
    - "app/package.json, app/server.js (build inputs for the fixed variant)"
    - "deploy/overlays/local/demoapp-patch.yaml (manifest Scenario 2 asserts bumped)"
    - "bootstrap/argocd/application.yaml (watches deploy/overlays/local on main)"
  provides:
    - "app/Dockerfile.fixed (green-path image for Scenario 2)"
    - "ci/smoke-test.sh (Jenkins + registry health check)"
    - "ci/tests/verify-jcasc.sh (no-wizard + JCasC + plugin-parity assertion)"
    - "ci/tests/scenario-1.sh (blocked-build assertion, CI-03)"
    - "ci/tests/scenario-2.sh (successful-deploy assertion, CI-04/CI-05)"
  affects:
    - "04-jenkins-provision (verify-jcasc.sh consumes ci/plugins.txt it creates)"
    - "04-pipeline-jenkinsfile (DOCKERFILE build param + demoapp-pipeline job)"
    - "04-scenario-verification (runs these scripts on the Windows target)"
tech-stack:
  added: []
  patterns:
    - "Wave 0 test scaffolds: pass/fail contract written before the pipeline"
    - "localhost-only targets (5001 registry, 8080 Jenkins) — no external network"
    - "colored ok/warn/die bash helpers mirroring app/build.sh"
    - "set -euo pipefail + non-zero exit on any assertion failure"
key-files:
  created:
    - app/Dockerfile.fixed
    - ci/smoke-test.sh
    - ci/tests/verify-jcasc.sh
    - ci/tests/scenario-1.sh
    - ci/tests/scenario-2.sh
  modified: []
decisions:
  - "Fixed variant is a separate Dockerfile.fixed selected via a DOCKERFILE build param, not a mutation of the vulnerable Dockerfile — keeps the Scenario 1 vuln artefact intact."
  - "Scenario scripts drive Jenkins via the REST buildWithParameters API and poll lastBuild/api/json — no Groovy, portable to the Windows target."
  - "Runtime execution deferred to the Windows/Rancher Desktop target; only static (bash -n, chmod, grep) validation performed on the macOS dev machine."
metrics:
  duration: ~8m
  completed: 2026-08-14
  tasks: 3
  files: 5
---

# Phase 4 Plan 04-test-scaffolds: CI Validation Harness Summary

Created the Wave 0 validation harness and the fixed image variant that later Phase 4 plans depend on: a `node:22-alpine` non-root Dockerfile for the green path plus four `set -euo pipefail` bash scripts that encode the observable pass/fail contract for CI-03/CI-04/CI-05 against localhost-only Jenkins (8080) and registry (5001) endpoints.

## What Was Built

- **app/Dockerfile.fixed** — mirrors `app/Dockerfile`'s build steps on a current `node:22-alpine` base, runs as the built-in non-root `node` user. This is the image Trivy passes (`--severity HIGH,CRITICAL --exit-code 1`) so Scenario 2 has a green-path input. The vulnerable `app/Dockerfile` (`node:14.21.3-alpine`) is left untouched as the Scenario 1 artefact.
- **ci/smoke-test.sh** — registry reachability (`localhost:5001/v2/` → `{}`), Jenkins controller poll (`localhost:8080/login`, accepts 200/403, 30×2s), and agent→docker-socket check (`docker exec jenkins-agent docker info`) with a Pitfall-1 hint on failure.
- **ci/tests/verify-jcasc.sh** — proves code-only provisioning: setup wizard bypassed (no `initialAdminPassword`), JCasC config loaded, and every short name in `ci/plugins.txt` present in `jenkins-plugin-cli --list`.
- **ci/tests/scenario-1.sh** — triggers `demoapp-pipeline` with `DOCKERFILE=Dockerfile`, polls `lastBuild`, asserts `result == FAILURE` and no new SHA tag in the registry (CI-03).
- **ci/tests/scenario-2.sh** — triggers with `DOCKERFILE=Dockerfile.fixed`, asserts `result == SUCCESS`, the git-SHA tag is in the registry, and `deploy/overlays/local/demoapp-patch.yaml` is bumped to `demoapp:<sha>` on `origin/main` (CI-04/CI-05).

Both scenario scripts exit 2 with guidance when `JENKINS_ADMIN_USER`/`JENKINS_ADMIN_PASSWORD` are unset.

## Tasks Completed

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Fixed non-vulnerable image variant | 966e609 | app/Dockerfile.fixed |
| 2 | smoke-test.sh + verify-jcasc.sh | 8116646 | ci/smoke-test.sh, ci/tests/verify-jcasc.sh |
| 3 | scenario-1.sh + scenario-2.sh | 02d691a | ci/tests/scenario-1.sh, ci/tests/scenario-2.sh |

## Verification

- All four scripts parse clean with `bash -n` (exit 0) and are mode `0755` (executable).
- `app/Dockerfile.fixed` contains `FROM node:22-alpine` + `USER node`; `app/Dockerfile` still `FROM node:14.21.3-alpine`.
- Scripts reference the exact downstream names: registry `localhost:5001`, job `demoapp-pipeline`, manifest `demoapp-patch.yaml`, params `DOCKERFILE=Dockerfile` / `DOCKERFILE=Dockerfile.fixed`.
- Runtime execution (docker/Jenkins/registry) is deferred to the Windows/Rancher Desktop target per project setup; only static offline checks were run here.

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None. The scripts are complete against the ground-truth interfaces documented in the plan. They necessarily reference artefacts created by later Plan 01 (`ci/plugins.txt`), Plan 02 (`jenkins`/`jenkins-agent` containers), and Plan 03 (`demoapp-pipeline` job, `DOCKERFILE` param) — this is the intended Wave 0 → later-wave contract, not a stub.

## Notes for Downstream Plans

- **04-jenkins-provision** must produce `ci/plugins.txt` (short-name list, `:version` optional) — `verify-jcasc.sh` reads it for parity, and containers must be named `jenkins` (controller) and `jenkins-agent` (agent).
- **04-pipeline-jenkinsfile** must expose a `DOCKERFILE` build parameter and name the job `demoapp-pipeline`; the BUMP stage must commit `demoapp:<short-sha>` into `deploy/overlays/local/demoapp-patch.yaml` on `main`.

## Self-Check: PASSED

All 5 created files exist on disk and all 3 task commits (966e609, 8116646, 02d691a) are present in git history.
