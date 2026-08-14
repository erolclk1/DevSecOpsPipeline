---
phase: 04-jenkins-ci
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - app/Dockerfile.fixed
  - ci/tests/verify-jcasc.sh
  - ci/tests/scenario-1.sh
  - ci/tests/scenario-2.sh
  - ci/smoke-test.sh
autonomous: true
requirements: [CI-03, CI-04, CI-05]
must_haves:
  truths:
    - "A fixed (non-vulnerable) image variant exists that Trivy passes with 0 HIGH/CRITICAL fixed findings"
    - "verify-jcasc.sh asserts installed plugins match ci/plugins.txt and no setup wizard is required"
    - "scenario-1.sh asserts a vulnerable build blocks at SCAN and pushes no new registry tag"
    - "scenario-2.sh asserts a fixed build pushes a SHA tag and bumps demoapp-patch.yaml in Git"
  artifacts:
    - path: "app/Dockerfile.fixed"
      provides: "node:22-alpine non-root image for the Scenario 2 green path"
      contains: "FROM node:22-alpine"
    - path: "ci/tests/scenario-1.sh"
      provides: "Blocked-build assertion (CI-03)"
      contains: "tags/list"
    - path: "ci/tests/scenario-2.sh"
      provides: "Successful-deploy assertion (CI-04, CI-05)"
      contains: "demoapp-patch.yaml"
    - path: "ci/tests/verify-jcasc.sh"
      provides: "Plugin parity + no-wizard assertion (CI-01, CI-07)"
      contains: "jenkins-plugin-cli"
    - path: "ci/smoke-test.sh"
      provides: "Jenkins + registry health check"
      contains: "localhost:8080"
  key_links:
    - from: "ci/tests/scenario-1.sh"
      to: "registry"
      via: "curl http://localhost:5001/v2/demoapp/tags/list"
      pattern: "tags/list"
    - from: "ci/tests/scenario-2.sh"
      to: "deploy/overlays/local/demoapp-patch.yaml"
      via: "git log / grep of new SHA tag"
      pattern: "demoapp-patch.yaml"
---

<objective>
Create the validation harness (Wave 0 test scaffolds) and the fixed image variant that Phase 4 needs BEFORE the Jenkins pipeline is built. These scripts define the observable pass/fail contract for every CI requirement, and the fixed Dockerfile provides the green-path input for Scenario 2.

Purpose: Every downstream task can then reference a concrete `<automated>` command instead of "MISSING". The fixed image gives Scenario 2 something Trivy will pass.
Output: `app/Dockerfile.fixed`, `ci/tests/verify-jcasc.sh`, `ci/tests/scenario-1.sh`, `ci/tests/scenario-2.sh`, `ci/smoke-test.sh`.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/04-jenkins-ci/04-RESEARCH.md
@.planning/phases/04-jenkins-ci/04-VALIDATION.md

<interfaces>
<!-- Ground-truth artifacts the tests assert against. Do NOT re-derive these; use exactly. -->

Registry topology (from app/build.sh, CLAUDE.md rule 3):
- Push/scan from host & agent daemon: `localhost:5001`
- Manifest hostname (in demoapp-patch.yaml): `host.rancher-desktop.internal:5001`
- Registry health: `curl -sf http://localhost:5001/v2/` returns `{}`
- Tag list: `curl -sf http://localhost:5001/v2/demoapp/tags/list` returns JSON `{"name":"demoapp","tags":[...]}`

Current vulnerable base (app/Dockerfile): `FROM node:14.21.3-alpine` (guarantees Trivy CRITICAL findings).
Manifest bumped by pipeline (deploy/overlays/local/demoapp-patch.yaml):
  image: host.rancher-desktop.internal:5001/demoapp:<sha>
Git image tag = `git rev-parse --short HEAD` (7 hex chars).
Jenkins controller URL once running: `http://localhost:8080` (dashboard, NOT /login wizard).
Repo remote: https://github.com/erolclk1/DevSecOpsPipeline.git (branch main).
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create the fixed (non-vulnerable) image variant for Scenario 2</name>
  <files>app/Dockerfile.fixed</files>
  <read_first>
    - app/Dockerfile (current vulnerable base node:14.21.3-alpine — replicate structure)
    - app/package.json (express 4.18.2, mysql 2.18.1 — dependencies must still install)
    - app/server.js (entrypoint is `node server.js`, listens on PORT 3000)
    - deploy/base/deployment.yaml (container runs on port 3000, has resource limits)
  </read_first>
  <action>
    Create `app/Dockerfile.fixed` — identical build steps to `app/Dockerfile` but on a current, patched base so Trivy passes the `--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1` gate. Exact contents:

    ```dockerfile
    FROM node:22-alpine

    WORKDIR /app

    COPY package.json package-lock.json* ./

    RUN npm install --production

    COPY server.js ./

    ENV PORT=3000

    EXPOSE 3000

    # Run as the built-in non-root 'node' user (defense-in-depth; Scenario 2 is the "secure" build)
    USER node

    CMD ["node", "server.js"]
    ```

    Do NOT modify `app/Dockerfile` (it must stay `node:14.21.3-alpine` — it is the intentionally vulnerable artefact for Scenario 1 / APP-03). This file is a separate variant selected by the pipeline via a `DOCKERFILE` build parameter in Plan 03.
  </action>
  <verify>
    <automated>test -f app/Dockerfile.fixed && grep -q '^FROM node:22-alpine' app/Dockerfile.fixed && grep -q '^USER node' app/Dockerfile.fixed && grep -q '^FROM node:14.21.3-alpine' app/Dockerfile</automated>
  </verify>
  <acceptance_criteria>
    - `app/Dockerfile.fixed` exists
    - `grep -q '^FROM node:22-alpine' app/Dockerfile.fixed` succeeds
    - `grep -q '^USER node' app/Dockerfile.fixed` succeeds
    - `grep -q 'CMD \["node", "server.js"\]' app/Dockerfile.fixed` succeeds
    - `app/Dockerfile` still contains `FROM node:14.21.3-alpine` (unchanged)
  </acceptance_criteria>
  <done>Two Dockerfiles coexist: `app/Dockerfile` (vulnerable, Scenario 1) and `app/Dockerfile.fixed` (patched non-root, Scenario 2).</done>
</task>

<task type="auto">
  <name>Task 2: Write verify-jcasc.sh + smoke-test.sh (Jenkins health + plugin parity)</name>
  <files>ci/tests/verify-jcasc.sh, ci/smoke-test.sh</files>
  <read_first>
    - .planning/phases/04-jenkins-ci/04-RESEARCH.md (Validation Architecture: CI-01/CI-07 test map)
    - .planning/phases/04-jenkins-ci/04-VALIDATION.md (Per-Task Verification Map, Manual-Only)
    - app/build.sh (bash style, colored ok/die helpers to mirror)
  </read_first>
  <action>
    Create `ci/smoke-test.sh` (chmod +x). It must exit non-zero on any failure. Contents:
    - `set -euo pipefail`
    - Assert registry: `curl -sf http://localhost:5001/v2/ | grep -q '{}'` else exit 1 with message "registry not reachable at localhost:5001".
    - Assert Jenkins controller up: poll `curl -sf -o /dev/null -w '%{http_code}' http://localhost:8080/login` up to 30 times (2s apart); pass when HTTP code is 200 or 403; fail after timeout.
    - Assert agent connected + docker reachable from agent: `docker exec jenkins-agent docker info >/dev/null 2>&1` (agent container name is `jenkins-agent` per Plan 02 docker-compose). Print "agent docker OK" on success; on failure print "agent cannot reach docker socket — check /var/run/docker.sock mount (Pitfall 1)".
    - Print `✓ smoke test passed` and exit 0.

    Create `ci/tests/verify-jcasc.sh` (chmod +x). It must exit non-zero on mismatch. Contents:
    - `set -euo pipefail`
    - Assert no setup wizard: `docker exec jenkins test ! -f /var/jenkins_home/secrets/initialAdminPassword` — the presence of that file means the wizard was NOT bypassed; fail if present (controller container name is `jenkins`).
    - Assert JCasC loaded: `docker exec jenkins sh -c 'test -f "$CASC_JENKINS_CONFIG" || test -f /var/jenkins_home/casc.yaml'`.
    - Plugin parity: build expected list from `ci/plugins.txt` short names (strip `:version`, ignore blank/`#` lines) and installed list from `docker exec jenkins jenkins-plugin-cli --list`. For each expected short name, assert it appears in the installed output; fail listing any missing plugin.
    - Print `✓ JCasC parity OK` and exit 0.
  </action>
  <verify>
    <automated>bash -n ci/smoke-test.sh && bash -n ci/tests/verify-jcasc.sh && test -x ci/smoke-test.sh && test -x ci/tests/verify-jcasc.sh</automated>
  </verify>
  <acceptance_criteria>
    - `ci/smoke-test.sh` exists, is executable (`test -x`), and `bash -n` parses clean
    - `ci/tests/verify-jcasc.sh` exists, is executable, and `bash -n` parses clean
    - `grep -q 'localhost:8080' ci/smoke-test.sh` succeeds
    - `grep -q 'localhost:5001/v2/' ci/smoke-test.sh` succeeds
    - `grep -q 'initialAdminPassword' ci/tests/verify-jcasc.sh` succeeds (wizard-bypass assertion)
    - `grep -q 'jenkins-plugin-cli --list' ci/tests/verify-jcasc.sh` succeeds
    - `grep -q 'set -euo pipefail' ci/smoke-test.sh` and same in verify-jcasc.sh
  </acceptance_criteria>
  <done>Two health/parity scripts exist and parse; both fail loudly (non-zero exit) when Jenkins is misconfigured.</done>
</task>

<task type="auto">
  <name>Task 3: Write scenario-1.sh (blocked build) + scenario-2.sh (successful deploy)</name>
  <files>ci/tests/scenario-1.sh, ci/tests/scenario-2.sh</files>
  <read_first>
    - app/build.sh (reference BUILD→SCAN→PUSH flow and registry curl patterns)
    - deploy/overlays/local/demoapp-patch.yaml (the file Scenario 2 must see bumped)
    - bootstrap/argocd/application.yaml (ArgoCD watches deploy/overlays/local on main)
    - .planning/phases/04-jenkins-ci/04-RESEARCH.md (Wave 0 Gaps section)
  </read_first>
  <action>
    Create `ci/tests/scenario-1.sh` (chmod +x, `set -euo pipefail`) — asserts the BLOCKED build (CI-03):
    - Capture tags before: `BEFORE=$(curl -sf http://localhost:5001/v2/demoapp/tags/list || echo '{}')`.
    - Trigger the vulnerable pipeline build. Accept the Jenkins job name `demoapp-pipeline` and build with parameter `DOCKERFILE=Dockerfile` (vulnerable). Use the Jenkins REST API with admin creds from env `JENKINS_ADMIN_USER`/`JENKINS_ADMIN_PASSWORD`:
      `curl -sf -X POST -u "$JENKINS_ADMIN_USER:$JENKINS_ADMIN_PASSWORD" "http://localhost:8080/job/demoapp-pipeline/buildWithParameters?DOCKERFILE=Dockerfile"`.
    - Poll the last build result via `http://localhost:8080/job/demoapp-pipeline/lastBuild/api/json` until `result` is non-null (timeout 10 min).
    - PASS condition: `result == "FAILURE"` AND the tag list is unchanged (`AFTER == BEFORE`, or the current git short SHA is NOT present in the tags list). Print `✓ Scenario 1: vulnerable build blocked, no new tag`. Any other outcome exits 1.

    Create `ci/tests/scenario-2.sh` (chmod +x, `set -euo pipefail`) — asserts the SUCCESSFUL deploy (CI-04, CI-05):
    - `SHA=$(git rev-parse --short HEAD)`.
    - Trigger the fixed pipeline build: `curl -sf -X POST -u "$JENKINS_ADMIN_USER:$JENKINS_ADMIN_PASSWORD" "http://localhost:8080/job/demoapp-pipeline/buildWithParameters?DOCKERFILE=Dockerfile.fixed"`.
    - Poll lastBuild until `result` non-null (timeout 10 min); require `result == "SUCCESS"`.
    - Assert registry tag present: `curl -sf http://localhost:5001/v2/demoapp/tags/list | grep -q "$SHA"`.
    - Assert manifest bumped in Git: `git fetch origin main` then `git log origin/main -1 --format='%s' -- deploy/overlays/local/demoapp-patch.yaml | grep -q "$SHA"` OR `git show origin/main:deploy/overlays/local/demoapp-patch.yaml | grep -q "demoapp:$SHA"`.
    - Print `✓ Scenario 2: fixed build deployed, tag+bump present`. Any failure exits 1.

    Both scripts must guard missing env: if `JENKINS_ADMIN_USER`/`JENKINS_ADMIN_PASSWORD` unset, print instruction to source `ci/.env` and exit 2.
  </action>
  <verify>
    <automated>bash -n ci/tests/scenario-1.sh && bash -n ci/tests/scenario-2.sh && test -x ci/tests/scenario-1.sh && test -x ci/tests/scenario-2.sh && grep -q 'FAILURE' ci/tests/scenario-1.sh && grep -q 'SUCCESS' ci/tests/scenario-2.sh</automated>
  </verify>
  <acceptance_criteria>
    - `ci/tests/scenario-1.sh` and `ci/tests/scenario-2.sh` exist, are executable, parse with `bash -n`
    - `grep -q 'tags/list' ci/tests/scenario-1.sh` succeeds
    - `grep -q 'FAILURE' ci/tests/scenario-1.sh` succeeds (blocked-build assertion)
    - `grep -q 'DOCKERFILE=Dockerfile.fixed' ci/tests/scenario-2.sh` succeeds
    - `grep -q 'demoapp-patch.yaml' ci/tests/scenario-2.sh` succeeds (bump assertion)
    - `grep -q 'SUCCESS' ci/tests/scenario-2.sh` succeeds
    - both scripts contain `set -euo pipefail`
  </acceptance_criteria>
  <done>Scenario 1 asserts block + no-push; Scenario 2 asserts pass + SHA tag + manifest bump. Both are runnable once the pipeline exists (Plan 03).</done>
</task>

</tasks>

<verification>
- `bash -n` parses all four scripts clean; all are executable.
- `app/Dockerfile.fixed` is `node:22-alpine` + `USER node`; `app/Dockerfile` unchanged (`node:14.21.3-alpine`).
- Scripts reference exact registry (`localhost:5001`), manifest (`demoapp-patch.yaml`), and job (`demoapp-pipeline`) names used by later plans.
</verification>

<success_criteria>
- All Wave 0 gaps from RESEARCH.md "Wave 0 Gaps" are created: verify-jcasc.sh, scenario-1.sh, scenario-2.sh, plus smoke-test.sh and the fixed Dockerfile.
- No script assumes external network targets; all hit localhost / the local registry / the local Jenkins.
</success_criteria>

<output>
After completion, create `.planning/phases/04-jenkins-ci/04-test-scaffolds-SUMMARY.md`.
</output>
