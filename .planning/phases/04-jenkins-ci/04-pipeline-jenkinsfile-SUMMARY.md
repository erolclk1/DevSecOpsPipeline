---
phase: 04-jenkins-ci
plan: 04-pipeline-jenkinsfile
subsystem: ci-pipeline
tags: [ci, jenkins, jenkinsfile, trivy, gitops, sbom, cyclonedx]
dependency-graph:
  requires:
    - "docker-builder agent label + DOCKERFILE param + github-token cred + demoapp-pipeline seed job (Plan 04-jenkins-provision)"
    - "app/Dockerfile + app/Dockerfile.fixed build targets (Plan 04-test-scaffolds / Phase 2)"
    - "deploy/overlays/local/demoapp-patch.yaml (the manifest BUMP rewrites)"
    - "ci/docker-compose.yml (the stack phase-4 / reset-jenkins drive; Plan 04-jenkins-provision)"
  provides:
    - "Jenkinsfile (repo root) — 4-stage declarative pipeline BUILD -> SCAN -> PUSH -> BUMP + SBOM archive"
    - "ci/jenkins-reset.sh — full JCasC reprovision (volume wipe + compose rebuild, no UI)"
    - "Makefile phase-4 / jenkins-stop / reset-jenkins targets driving docker compose"
  affects:
    - "04-scenario-verification (scenario-1.sh / scenario-2.sh run this pipeline on the Windows target)"
    - "Phase 5 Falco demo (deployed image originates from this pipeline's PUSH + BUMP)"
tech-stack:
  added: []
  patterns:
    - "Declarative pipeline, all stages on the socket-owning docker-builder agent (controller never touches the daemon)"
    - "Trivy evidence-before-gate ordering: SBOM + JSON report emitted BEFORE the --exit-code 1 gate so blocked builds still archive artefacts (RESEARCH Pitfall 6)"
    - "GitOps boundary: pipeline pushes an image tag + commits a manifest bump to Git; never kubectl apply (CLAUDE.md rule 1)"
    - "Loop guard: BUMP commit message ends with [skip ci] to break the manifest-commit -> rebuild cycle (RESEARCH Pitfall 2)"
    - "Host vs cluster registry split: docker push uses localhost:5001; the manifest yq-writes host.rancher-desktop.internal:5001 (CLAUDE.md rule 3)"
key-files:
  created:
    - Jenkinsfile
    - ci/jenkins-reset.sh
  modified:
    - Makefile
decisions:
  - "Ported the proven app/build.sh flow (tag = git short SHA, build, Trivy HIGH/CRITICAL gate, push) into Jenkins verbatim rather than reinventing it (RESEARCH: port build.sh, do not reinvent)."
  - "SCAN scans the local docker daemon image via --image-src docker (no in-container registry network needed; RESEARCH Open Q2)."
  - "Gate uses --ignore-unfixed --scanners vuln so only actionable fixed HIGH/CRITICAL CVEs fail the build; the separate SBOM/report scans run unconditionally for evidence."
  - "Replaced the stale single-container Makefile scaffold (docker run mounting ~/.rd/docker.sock on the controller — wrong for Windows/WSL2 and violates socket-on-agent) with docker-compose-driven phase-4 / reset-jenkins targets."
metrics:
  duration: ~5m
  completed: 2026-08-14
  tasks: 2
  files: 3
---

# Phase 4 Plan 04-pipeline-jenkinsfile: CI Pipeline Jenkinsfile Summary

Authored the repo-root `Jenkinsfile` — a four-stage declarative pipeline (BUILD, SCAN, PUSH, BUMP) that ports the proven `app/build.sh` flow into Jenkins on the `docker-builder` agent and adds the GitOps manifest bump — plus `ci/jenkins-reset.sh` and the Makefile `phase-4` / `jenkins-stop` / `reset-jenkins` wiring that retires the old single-container scaffold in favour of the two-container docker-compose stack. Satisfies CI-02 (SHA tag), CI-03 (Trivy gate blocks + no push), CI-04 (push after pass), CI-05 (yq bump + git push, never kubectl), CI-06 (CycloneDX SBOM archived every run).

## What Was Built

- **Jenkinsfile** (repo root, 64 lines) — `agent { label 'docker-builder' }`, `timestamps()` + `ansiColor('xterm')`, a `DOCKERFILE` string param (default `Dockerfile`, fixed run uses `Dockerfile.fixed`), and four stages:
  - **BUILD** — resolves `GIT_SHA = git rev-parse --short HEAD`, then `docker build -f app/${DOCKERFILE} -t localhost:5001/demoapp:${GIT_SHA} app/` (CI-02, SHA-only tag).
  - **SCAN** — first emits evidence unconditionally (`trivy image --image-src docker --format cyclonedx` SBOM + a HIGH/CRITICAL JSON report `|| true`), then runs the gate `trivy image --image-src docker --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --scanners vuln --no-progress`; a non-zero exit fails the stage before PUSH (CI-03, Pitfall 6 ordering).
  - **PUSH** — `docker push localhost:5001/demoapp:${GIT_SHA}` (runs only after SCAN passes; CI-04).
  - **BUMP** — under `withCredentials([string(credentialsId: 'github-token', ...)])`, `yq -i` rewrites `deploy/overlays/local/demoapp-patch.yaml` to `host.rancher-desktop.internal:5001/demoapp:${GIT_SHA}` (CLUSTER hostname), commits `ci: bump demoapp to ${GIT_SHA} [skip ci]`, and pushes `HEAD:main` via the PAT (CI-05, Pitfall 2 loop guard).
  - **post { always }** — `archiveArtifacts 'demoapp-sbom.json, trivy-report.json', allowEmptyArchive: true` so the SBOM is captured on both passing and blocked builds (CI-06).
- **ci/jenkins-reset.sh** — `set -euo pipefail`, colored ok/warn/die helpers mirroring `app/build.sh`; requires `ci/.env` (else prints the copy-from-example hint and `exit 2`), then `docker compose -f ci/docker-compose.yml down -v` (wipes jenkins_home / trivy_cache / agent_work), `up -d --build`, polls `http://localhost:8080/login` up to 60×5s, and points the operator at `ci/tests/verify-jcasc.sh`.
- **Makefile** — Phase 4 section rewritten: `phase-4` (`docker compose ... up -d --build`), `jenkins-stop` (`docker compose ... down`, keeps volumes), `reset-jenkins` (delegates to `ci/jenkins-reset.sh`). The old `jenkins-start` target (single `docker run` mounting `~/.rd/docker.sock` on the controller) is deleted; `.PHONY` now lists `phase-4` + `jenkins-stop` and drops `jenkins-start`. `down:` still resolves via `jenkins-stop`.

## Tasks Completed

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Repo-root Jenkinsfile (BUILD/SCAN/PUSH/BUMP + SBOM archive) | 84d38f6 | Jenkinsfile |
| 2 | jenkins-reset.sh + Makefile phase-4 / reset-jenkins wiring | 6dd8320 | ci/jenkins-reset.sh, Makefile |

## Verification

- **Task 1 gate (all PASS):** `Jenkinsfile` exists (64 lines > 60); no `kubectl`; no `:latest`; contains `label 'docker-builder'`, `git rev-parse --short HEAD`, `--severity HIGH,CRITICAL --ignore-unfixed`, `--exit-code 1`, `docker push`, `yq -i`, `credentialsId: 'github-token'`, `skip ci`, `format cyclonedx`, `archiveArtifacts`, `host.rancher-desktop.internal:5001`.
- **Task 2 gate (all PASS):** `ci/jenkins-reset.sh` executable + `bash -n` clean + `docker compose ... down -v` + `set -euo pipefail`; Makefile has `phase-4:` and `docker compose ... up -d --build`; no `rd/docker.sock`; `reset-jenkins:` delegates to the script. `make -n phase-4`, `make -n jenkins-stop`, `make -n reset-jenkins` all render without a Makefile syntax error; `jenkins-start` fully removed.
- **Runtime (deferred to Windows/Rancher Desktop target, per project convention):** `make phase-4` → build `demoapp-pipeline`; `ci/tests/scenario-1.sh` (vulnerable `DOCKERFILE=Dockerfile` fails at SCAN, no new registry tag) and `ci/tests/scenario-2.sh` (`DOCKERFILE=Dockerfile.fixed` passes, `demoapp:<sha>` pushed, `demoapp-patch.yaml` bumped on main). macOS is the code-only dev machine, so no live docker/Jenkins/registry run was performed here.

## Deviations from Plan

None — plan executed exactly as written (both tasks used the verbatim Jenkinsfile and Makefile block specified in the plan).

## Known Stubs

None. The Jenkinsfile and reset script are complete against the documented Plan 02 contracts (`docker-builder` label, `DOCKERFILE` param, `github-token` credential, `demoapp-pipeline` job) and the Plan 01 `Dockerfile.fixed` build target. Their runtime dependencies (`ci/docker-compose.yml`, `app/Dockerfile.fixed`) are produced by the sibling Phase 4 waves and combined at merge — an intended cross-wave contract, not a stub.

## User Setup Required

The BUMP stage pushes to `origin/main` using the `github-token` credential. The operator must have created `ci/.env` from `ci/.env.example` with `GITHUB_TOKEN` set to a fine-grained PAT (Contents: Read/Write on `erolclk1/DevSecOpsPipeline`) — the one secret Jenkins cannot self-provision (also flagged by Plan 04-jenkins-provision).

## Self-Check: PASSED

Both created files (`Jenkinsfile`, `ci/jenkins-reset.sh`) and the modified `Makefile` exist on disk; both task commits (84d38f6, 6dd8320) are present in git history.
