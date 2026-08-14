---
phase: 04-jenkins-ci
plan: 04-jenkins-provision
subsystem: ci-controller
tags: [ci, jenkins, jcasc, docker-compose, plugins, credentials]
dependency-graph:
  requires:
    - "ci/plugins.txt consumed by verify-jcasc.sh (Plan 04-test-scaffolds parity check)"
    - "container names jenkins / jenkins-agent expected by smoke-test.sh"
  provides:
    - "ci/controller.Dockerfile (Jenkins 2.555.3-lts-jdk21, wizard off, plugins baked)"
    - "ci/agent.Dockerfile (docker CLI + Trivy v0.72.0 + yq v4.45.1 + git; auto-connect)"
    - "ci/agent-entrypoint.sh (JNLP secret auto-fetch)"
    - "ci/plugins.txt (12 plugins pinned to explicit versions — CI-07)"
    - "ci/docker-compose.yml (controller no-socket + agent socket-mounted)"
    - "ci/.env.example (committed placeholders; ci/.env gitignored)"
    - "ci/jcasc/jenkins.yaml (security, github-token cred, docker-builder node, demoapp-pipeline seed job)"
  affects:
    - "04-pipeline-jenkinsfile (consumes docker-builder label, DOCKERFILE param, github-token cred, demoapp-pipeline job)"
    - "04-scenario-verification (runs smoke-test.sh / verify-jcasc.sh against these containers on the Windows target)"
tech-stack:
  added:
    - "Jenkins 2.555.3-lts-jdk21 (controller)"
    - "jenkins/inbound-agent:latest-jdk21 (agent base) + Trivy v0.72.0 + yq v4.45.1"
    - "12 pinned Jenkins plugins (JCasC, job-dsl, docker-workflow, credentials, git, matrix-auth, ...)"
  patterns:
    - "Configuration-as-Code: controller boots fully configured, no setup wizard, no UI clicks (CI-01)"
    - "Docker socket mounted on the AGENT only — controller never touches the daemon (GitOps + attack-surface boundary)"
    - "Inbound agent auto-connects by fetching its JNLP secret with admin creds (no manual secret paste)"
    - "Secrets via \${VAR} env interpolation from gitignored ci/.env; only ci/.env.example tracked"
key-files:
  created:
    - ci/controller.Dockerfile
    - ci/agent.Dockerfile
    - ci/agent-entrypoint.sh
    - ci/plugins.txt
    - ci/docker-compose.yml
    - ci/.env.example
    - ci/jcasc/jenkins.yaml
  modified:
    - .gitignore
decisions:
  - "Plugin versions resolved live from plugins.jenkins.io at execute time (latest builds as of 2026-08) rather than copied from stale examples; frozen into ci/plugins.txt with explicit versions."
  - "Agent auto-connects via JNLP secret fetched with admin credentials — fully reproducible from `docker compose up` with no manual token paste."
  - "numExecutors: 0 on the controller forces every stage onto the docker-builder agent (which owns the socket + Trivy + yq)."
  - "Runtime bring-up (compose up, smoke-test.sh, verify-jcasc.sh) deferred to the Windows/Rancher Desktop target per project convention; `docker compose config` validated statically on the macOS dev machine."
metrics:
  duration: ~12m
  completed: 2026-08-14
  tasks: 3
  files: 8
---

# Phase 4 Plan 04-jenkins-provision: JCasC Jenkins Provisioning Summary

Provisioned a fully reproducible Jenkins entirely from Configuration-as-Code: a custom controller image (`jenkins/jenkins:2.555.3-lts-jdk21`) with the setup wizard disabled and 12 pinned plugins baked in, a socket-mounted `docker-builder` agent image bundling docker CLI + Trivy v0.72.0 + yq v4.45.1 + git that auto-connects by fetching its own JNLP secret, and a `ci/jcasc/jenkins.yaml` defining the security realm, the `github-token` credential, the `docker-builder` inbound node, and a parameterized `demoapp-pipeline` seed job pointing at the repo-root `Jenkinsfile`. Satisfies CI-01 (JCasC controller, no wizard) and CI-07 (pinned plugins).

## What Was Built

- **ci/controller.Dockerfile** — `jenkins/jenkins:2.555.3-lts-jdk21`, `JAVA_OPTS=-Djenkins.install.runSetupWizard=false`, `CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml`, bakes `plugins.txt` via `jenkins-plugin-cli`.
- **ci/agent.Dockerfile** — `jenkins/inbound-agent:latest-jdk21` + `docker.io` + git + Trivy v0.72.0 (contrib install.sh) + yq v4.45.1; entrypoint auto-connects.
- **ci/agent-entrypoint.sh** — waits for `/login`, fetches the agent secret from `/computer/docker-builder/slave-agent.jnlp` with admin creds (30× retry), then `exec jenkins-agent`.
- **ci/plugins.txt** — 12 plugins, each pinned to an explicit version resolved live from plugins.jenkins.io (no `:latest`, no bare names): configuration-as-code, workflow-aggregator, job-dsl, pipeline-stage-view, docker-workflow, credentials, credentials-binding, git, git-client, timestamper, ansicolor, matrix-auth.
- **ci/docker-compose.yml** — `jenkins` controller (ports 8080/50000, JCasC mounted read-only, NO socket) + `jenkins-agent` (host `/var/run/docker.sock` bind, trivy_cache + agent_work volumes, `JENKINS_AGENT_NAME=docker-builder`).
- **ci/.env.example** — committed placeholders for `JENKINS_ADMIN_USER/PASSWORD`, `GITHUB_TOKEN`, `GIT_USER`.
- **ci/jcasc/jenkins.yaml** — local security realm (env-interpolated admin, no signup), `loggedInUsersCanDoAnything`, `numExecutors: 0`, `docker-builder` permanent inbound node, `github-token` Secret text credential, and the `demoapp-pipeline` `pipelineJob` with a `DOCKERFILE` string param and `cpsScm { scriptPath('Jenkinsfile') }` against `github.com/erolclk1/DevSecOpsPipeline.git` branch `main`.
- **.gitignore** — appended `ci/.env` (keeps existing `node_modules/`, `.env.phase2`; `ci/.env.example` stays tracked).

## Tasks Completed

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Controller + agent Dockerfiles, entrypoint, plugins.txt | ab6dd19 | ci/controller.Dockerfile, ci/agent.Dockerfile, ci/agent-entrypoint.sh, ci/plugins.txt |
| 2 | docker-compose.yml + .env.example + .gitignore | e805981 | ci/docker-compose.yml, ci/.env.example, .gitignore |
| 3 | JCasC jenkins.yaml (security, credential, node, seed job) | b5e323e | ci/jcasc/jenkins.yaml |

## Verification

- Task 1: all files present, `bash -n ci/agent-entrypoint.sh` clean, controller pins `2.555.3-lts-jdk21` + `runSetupWizard=false`, agent has `v0.72.0` + `yq`, `plugins.txt` has no `:latest` and includes `configuration-as-code:`. PASS.
- Task 2: socket present under agent only, controller block has no `docker.sock`, container names `jenkins` / `jenkins-agent`, JCasC read-only mount, `ci/.env` ignored, `.env.example` has `GITHUB_TOKEN`. PASS.
- Task 3: all contract strings present (`demoapp-pipeline`, `scriptPath('Jenkinsfile')`, `id: "github-token"`, `labelString: "docker-builder"`, `stringParam('DOCKERFILE'`, `${GITHUB_TOKEN}`, `${JENKINS_ADMIN_PASSWORD}`); YAML parses valid via PyYAML. PASS.
- Plan-level: `docker compose -f ci/docker-compose.yml config` resolves cleanly (throwaway `.env` used then removed; `ci/.env` confirmed git-ignored). Working tree clean.

## Deviations from Plan

None — plan executed exactly as written. (Environment note: PyYAML was not preinstalled on the dev machine; installed transiently to run the plan's YAML-validity check. No project files affected.)

## Deferred (runtime on Windows/Rancher Desktop target)

Per project convention (macOS is the code-only dev machine), full runtime bring-up is deferred to the Windows/Rancher Desktop target:
- `docker compose up -d --build` then `bash ci/smoke-test.sh` (controller on 8080, agent → docker socket).
- `bash ci/tests/verify-jcasc.sh` (no initialAdminPassword, JCasC loaded, installed plugins match plugins.txt, `demoapp-pipeline` present).
- Confirm the WSL2 socket mount `/var/run/docker.sock` (RESEARCH Pitfall 1); if `docker exec jenkins-agent docker info` fails, the mount path is the cause.
- Confirm agent base image arch: on arm64 targets, swap the yq asset to `yq_linux_arm64`.

## Known Stubs

None. All artefacts are complete against the documented interfaces. The seed job references the repo-root `Jenkinsfile` produced by Plan 04-pipeline-jenkinsfile and the `demoapp-pipeline`/`DOCKERFILE`/`github-token` contracts consumed by Plans 03 and the scenario scripts — intended cross-wave contracts, not stubs.

## User Setup Required

Before the BUMP stage can push to `main`, the operator must create `ci/.env` from `ci/.env.example` and set `GITHUB_TOKEN` to a fine-grained PAT with Contents: Read/Write on `erolclk1/DevSecOpsPipeline` (the only secret Jenkins cannot self-provision).

## Self-Check: PASSED

All 8 files (7 ci/ artefacts + SUMMARY) exist on disk, `.gitignore` carries the `ci/.env` rule, and all 3 task commits (ab6dd19, e805981, b5e323e) are present in git history.
