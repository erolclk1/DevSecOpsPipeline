---
phase: 04-jenkins-ci
plan: 03
type: execute
wave: 3
depends_on: ["04-02"]
files_modified:
  - Jenkinsfile
  - ci/jenkins-reset.sh
  - Makefile
autonomous: true
requirements: [CI-02, CI-03, CI-04, CI-05, CI-06]
must_haves:
  truths:
    - "BUILD stage tags the image with the git short SHA, never :latest"
    - "SCAN stage fails the build on HIGH/CRITICAL fixed CVEs; a failing scan stops the pipeline before PUSH"
    - "PUSH stage runs only after SCAN passes and pushes demoapp:<sha> to localhost:5001"
    - "BUMP stage yq-edits demoapp-patch.yaml, commits with [skip ci], and pushes to main via the github-token PAT"
    - "A CycloneDX SBOM is archived as a build artefact on every run (including blocked builds)"
    - "jenkins-reset.sh wipes the volumes and reprovisions Jenkins from JCasC with no UI steps"
  artifacts:
    - path: "Jenkinsfile"
      provides: "4-stage declarative pipeline (BUILD, SCAN, PUSH, BUMP) on the docker-builder agent"
      contains: "label 'docker-builder'"
      min_lines: 60
    - path: "ci/jenkins-reset.sh"
      provides: "Volume wipe + docker compose rebuild reprovision"
      contains: "docker compose"
    - path: "Makefile"
      provides: "phase-4 + reset-jenkins targets driving docker compose"
      contains: "phase-4"
  key_links:
    - from: "Jenkinsfile SCAN stage"
      to: "PUSH stage"
      via: "non-zero trivy --exit-code 1 aborts before PUSH"
      pattern: "--exit-code 1"
    - from: "Jenkinsfile BUMP stage"
      to: "deploy/overlays/local/demoapp-patch.yaml"
      via: "yq -i in-place image edit + git push HEAD:main"
      pattern: "yq -i"
    - from: "Jenkinsfile BUMP stage"
      to: "github-token credential"
      via: "withCredentials string binding"
      pattern: "credentialsId: 'github-token'"
---

<objective>
Author the repo-root `Jenkinsfile` — the four declarative stages (BUILD, SCAN, PUSH, BUMP) that port the proven `app/build.sh` flow into Jenkins and add the GitOps manifest bump — plus `ci/jenkins-reset.sh` and the Makefile `phase-4` / `reset-jenkins` wiring that replaces the old single-container scaffold.

Purpose: Satisfies CI-02 (SHA tag), CI-03 (Trivy gate blocks + no push), CI-04 (push after pass), CI-05 (yq bump + git push, never kubectl), CI-06 (CycloneDX SBOM archived every run).
Output: Jenkinsfile, ci/jenkins-reset.sh, updated Makefile.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/ROADMAP.md
@.planning/phases/04-jenkins-ci/04-RESEARCH.md

<interfaces>
<!-- Ground truth to port. RESEARCH.md: "port build.sh, do not reinvent." -->

From app/build.sh (proven BUILD->SCAN->PUSH):
  TAG = git rev-parse --short HEAD
  PUSH image  = localhost:5001/demoapp:${TAG}
  Trivy gate  = trivy image --severity HIGH,CRITICAL --exit-code 1 --no-progress <img>
  Registry health = curl -sf http://localhost:5001/v2/

From deploy/overlays/local/demoapp-patch.yaml (the file BUMP edits):
  spec.template.spec.containers[0].image: host.rancher-desktop.internal:5001/demoapp:6af2848
  --> BUMP sets it to host.rancher-desktop.internal:5001/demoapp:${GIT_SHA}  (CLUSTER hostname, port 5001)

Contracts from Plan 02 (must match exactly):
  agent label        = docker-builder
  build parameter    = DOCKERFILE (default 'Dockerfile'; fixed run uses 'Dockerfile.fixed')
  credential id      = github-token  (Secret text = GitHub PAT)
  seed job scriptPath = Jenkinsfile (repo root)
  Trivy cache volume mounted at /home/jenkins/.trivy-cache on the agent

Repo: https://github.com/erolclk1/DevSecOpsPipeline.git , branch main
CLAUDE.md rules: NO kubectl anywhere in Jenkinsfile; tags always git short SHA (never :latest).
RESEARCH Pitfall 2: BUMP commit MUST include [skip ci] to avoid an infinite build loop.
RESEARCH Pitfall 6: generate SBOM + report BEFORE the failing --exit-code 1 gate so blocked builds still archive evidence.
RESEARCH Open Q2: scan the local daemon image with --image-src docker (no in-container registry network needed).
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Author the repo-root Jenkinsfile (BUILD, SCAN, PUSH, BUMP + SBOM archive)</name>
  <files>Jenkinsfile</files>
  <read_first>
    - app/build.sh (the exact flow to port: tag, build, trivy gate, push, registry curl)
    - deploy/overlays/local/demoapp-patch.yaml (the image line BUMP rewrites; CLUSTER hostname host.rancher-desktop.internal:5001)
    - .planning/phases/04-jenkins-ci/04-RESEARCH.md (Code Examples: SCAN gate + SBOM, BUMP stage, GIT_SHA + BUILD)
    - app/Dockerfile.fixed (the DOCKERFILE=Dockerfile.fixed build target created in Plan 01)
  </read_first>
  <action>
    Create `Jenkinsfile` at the repo ROOT (not under ci/). Declarative pipeline, all stages on the agent. Exact content:

    ```groovy
    pipeline {
      agent { label 'docker-builder' }
      options { timestamps() ; ansiColor('xterm') }
      parameters {
        string(name: 'DOCKERFILE', defaultValue: 'Dockerfile',
               description: 'Dockerfile (vulnerable) or Dockerfile.fixed (patched)')
      }
      environment {
        TRIVY_CACHE = "/home/jenkins/.trivy-cache"
        HOST_REG    = "localhost:5001"
        CLUSTER_REG = "host.rancher-desktop.internal:5001"
        GIT_SHA     = ""
      }
      stages {
        stage('BUILD') {
          steps {
            script { env.GIT_SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim() }
            sh 'docker build -f app/${DOCKERFILE} -t ${HOST_REG}/demoapp:${GIT_SHA} app/'
          }
        }
        stage('SCAN') {
          steps {
            // 1) Evidence FIRST (Pitfall 6): SBOM + JSON report before the gate, so blocked builds still archive artefacts
            sh '''
              trivy image --image-src docker --format cyclonedx \
                --output demoapp-sbom.json --cache-dir "$TRIVY_CACHE" ${HOST_REG}/demoapp:${GIT_SHA}
              trivy image --image-src docker --severity HIGH,CRITICAL --format json \
                --output trivy-report.json --cache-dir "$TRIVY_CACHE" ${HOST_REG}/demoapp:${GIT_SHA} || true
            '''
            // 2) The gate (CI-03): non-zero exit fails the stage and stops the pipeline before PUSH
            sh '''
              trivy image --image-src docker --severity HIGH,CRITICAL --ignore-unfixed \
                --exit-code 1 --scanners vuln --no-progress \
                --cache-dir "$TRIVY_CACHE" ${HOST_REG}/demoapp:${GIT_SHA}
            '''
          }
        }
        stage('PUSH') {
          steps {
            sh 'docker push ${HOST_REG}/demoapp:${GIT_SHA}'
          }
        }
        stage('BUMP') {
          steps {
            withCredentials([string(credentialsId: 'github-token', variable: 'GH_TOKEN')]) {
              sh '''
                yq -i '.spec.template.spec.containers[0].image = "'"${CLUSTER_REG}"'/demoapp:'"${GIT_SHA}"'"' \
                  deploy/overlays/local/demoapp-patch.yaml
                git config user.email "jenkins@thesis.local"
                git config user.name  "jenkins-ci"
                git add deploy/overlays/local/demoapp-patch.yaml
                git commit -m "ci: bump demoapp to ${GIT_SHA} [skip ci]"
                git push https://${GH_TOKEN}@github.com/erolclk1/DevSecOpsPipeline.git HEAD:main
              '''
            }
          }
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'demoapp-sbom.json, trivy-report.json', allowEmptyArchive: true
        }
      }
    }
    ```

    Hard constraints (verify before finishing):
    - NO `kubectl` token anywhere in the file (CLAUDE.md rule 1).
    - NO `:latest` tag; image is always `demoapp:${GIT_SHA}` (CLAUDE.md rule 4 / CI-02).
    - Push uses HOST_REG `localhost:5001`; the MANIFEST written by yq uses CLUSTER_REG `host.rancher-desktop.internal:5001` (RESEARCH: never push the cluster hostname over the network from the agent).
    - BUMP commit message ends with `[skip ci]` (Pitfall 2 loop guard).
    - `archiveArtifacts` is in `post { always }` with `allowEmptyArchive: true` so the SBOM is captured on both passing and blocked builds (CI-06 + Pitfall 6).
    - `ansiColor` requires the ansicolor plugin and `timestamps` the timestamper plugin — both are in ci/plugins.txt from Plan 02.
  </action>
  <verify>
    <automated>test -f Jenkinsfile && ! grep -q 'kubectl' Jenkinsfile && ! grep -q ':latest' Jenkinsfile && grep -q "label 'docker-builder'" Jenkinsfile && grep -q -- '--exit-code 1' Jenkinsfile && grep -q 'yq -i' Jenkinsfile && grep -q "credentialsId: 'github-token'" Jenkinsfile && grep -q 'skip ci' Jenkinsfile && grep -q 'format cyclonedx' Jenkinsfile && grep -q 'archiveArtifacts' Jenkinsfile && grep -q 'host.rancher-desktop.internal:5001' Jenkinsfile</automated>
  </verify>
  <acceptance_criteria>
    - `Jenkinsfile` exists at repo root with at least 60 lines
    - `! grep -q 'kubectl' Jenkinsfile` succeeds (GitOps boundary)
    - `! grep -q ':latest' Jenkinsfile` succeeds (SHA-only tags)
    - `grep -q "label 'docker-builder'" Jenkinsfile` succeeds
    - `grep -q 'git rev-parse --short HEAD' Jenkinsfile` succeeds (CI-02)
    - `grep -q -- '--severity HIGH,CRITICAL --ignore-unfixed' Jenkinsfile` and `grep -q -- '--exit-code 1' Jenkinsfile` succeed (CI-03)
    - `grep -q 'docker push' Jenkinsfile` succeeds (CI-04)
    - `grep -q 'yq -i' Jenkinsfile`, `grep -q "credentialsId: 'github-token'" Jenkinsfile`, `grep -q 'skip ci' Jenkinsfile` succeed (CI-05 + loop guard)
    - `grep -q 'format cyclonedx' Jenkinsfile` and `grep -q 'archiveArtifacts' Jenkinsfile` succeed (CI-06)
    - `grep -q 'host.rancher-desktop.internal:5001' Jenkinsfile` succeeds (manifest uses cluster hostname)
  </acceptance_criteria>
  <done>Repo-root Jenkinsfile runs BUILD->SCAN->PUSH->BUMP on the docker-builder agent, gates on Trivy, bumps the manifest with a [skip ci] commit, and archives the CycloneDX SBOM on every run.</done>
</task>

<task type="auto">
  <name>Task 2: jenkins-reset.sh + Makefile phase-4 / reset-jenkins wiring</name>
  <files>ci/jenkins-reset.sh, Makefile</files>
  <read_first>
    - Makefile (lines 160-188: jenkins-start / jenkins-stop / reset-jenkins scaffold to REPLACE with docker compose)
    - ci/docker-compose.yml (from Plan 02 — the compose file these targets drive)
    - app/build.sh (colored ok/die bash helper style to mirror)
  </read_first>
  <action>
    Create `ci/jenkins-reset.sh` (chmod +x, first line `#!/usr/bin/env bash`, then `set -euo pipefail`). Fully reprovision from JCasC with no UI steps:
    - Require `ci/.env`: if `[ ! -f ci/.env ]`, print "copy ci/.env.example to ci/.env and fill GITHUB_TOKEN + admin creds" and `exit 2`.
    - `docker compose -f ci/docker-compose.yml down -v` (removes jenkins_home, trivy_cache, agent_work volumes -> clean slate).
    - `docker compose -f ci/docker-compose.yml up -d --build`.
    - Wait for controller: loop up to 60 times, `curl -sf -o /dev/null http://localhost:8080/login` then break; `sleep 5` between tries.
    - Print "Run: bash ci/tests/verify-jcasc.sh to confirm parity".
    - Print `✓ Jenkins reset — reprovisioned from JCasC`.

    Update the `Makefile` Phase 4 section. The current targets `jenkins-start` / `jenkins-stop` / `reset-jenkins` use a single `docker run` mounting `~/.rd/docker.sock` on the controller (WRONG for Windows/WSL2 and violates socket-on-agent). Replace that whole block with docker-compose-driven targets. Add `phase-4` to the `.PHONY` list and implement:
    ```make
    ## Phase 4: build + start Jenkins (controller + agent) from docker-compose + JCasC
    phase-4:
    	@docker compose -f ci/docker-compose.yml up -d --build
    	@echo "✓ Jenkins starting at http://localhost:$(JENKINS_PORT) (JCasC, no wizard)"
    	@echo "  Verify: bash ci/smoke-test.sh && bash ci/tests/verify-jcasc.sh"

    ## Stop Jenkins (keep volumes)
    jenkins-stop:
    	@docker compose -f ci/docker-compose.yml down 2>/dev/null && echo "✓ Jenkins stopped" || echo "  Jenkins was not running"

    ## Wipe Jenkins volumes and reprovision from JCasC
    reset-jenkins:
    	@bash ci/jenkins-reset.sh
    ```
    Delete the old `jenkins-start` target that mounts `~/.rd/docker.sock`. Keep `JENKINS_PORT := 8080`. Ensure the `down:` target still calls a valid stop target (`jenkins-stop`), and update `.PHONY` to include `phase-4`.
  </action>
  <verify>
    <automated>test -x ci/jenkins-reset.sh && bash -n ci/jenkins-reset.sh && grep -q 'docker compose -f ci/docker-compose.yml down -v' ci/jenkins-reset.sh && grep -q 'phase-4:' Makefile && grep -q 'docker compose -f ci/docker-compose.yml up -d --build' Makefile && ! grep -q 'rd/docker.sock' Makefile</automated>
  </verify>
  <acceptance_criteria>
    - `ci/jenkins-reset.sh` exists, is executable, parses with `bash -n`
    - `grep -q 'docker compose -f ci/docker-compose.yml down -v' ci/jenkins-reset.sh` succeeds (volume wipe)
    - `grep -q 'set -euo pipefail' ci/jenkins-reset.sh` succeeds
    - `grep -q 'phase-4:' Makefile` succeeds and `make -n phase-4` runs without a Makefile syntax error
    - `grep -q 'docker compose -f ci/docker-compose.yml up -d --build' Makefile` succeeds
    - `! grep -q 'rd/docker.sock' Makefile` succeeds (old wrong socket mount removed)
    - `grep -q 'reset-jenkins:' Makefile` succeeds and its body calls `ci/jenkins-reset.sh`
  </acceptance_criteria>
  <done>Reset script and Makefile drive the two-container compose stack; the stale `~/.rd/docker.sock` single-container scaffold is gone.</done>
</task>

</tasks>

<verification>
- Jenkinsfile: `grep` gate checks above all pass; no `kubectl`, no `:latest`.
- After `make phase-4` (or `bash ci/jenkins-reset.sh`) the `demoapp-pipeline` job is buildable.
- Run `ci/tests/scenario-1.sh` (Plan 01): vulnerable build (`DOCKERFILE=Dockerfile`) fails at SCAN, no new registry tag.
- Run `ci/tests/scenario-2.sh` (Plan 01): fixed build (`DOCKERFILE=Dockerfile.fixed`) passes, `demoapp:<sha>` in registry, `demoapp-patch.yaml` bumped on main.
</verification>

<success_criteria>
- CI-02: BUILD tags with git short SHA, never `:latest`.
- CI-03: vulnerable build fails at SCAN; `curl http://localhost:5001/v2/demoapp/tags/list` shows no new tag.
- CI-04: fixed build pushes `demoapp:<sha>` only after SCAN passes.
- CI-05: `demoapp-patch.yaml` bumped via yq, committed `[skip ci]`, pushed to main; no `kubectl` anywhere.
- CI-06: `demoapp-sbom.json` archived as a build artefact on every run.
</success_criteria>

<output>
After completion, create `.planning/phases/04-jenkins-ci/04-pipeline-jenkinsfile-SUMMARY.md`.
</output>
