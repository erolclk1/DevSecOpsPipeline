---
phase: 04-jenkins-ci
plan: 02
type: execute
wave: 2
depends_on: ["04-01"]
files_modified:
  - ci/controller.Dockerfile
  - ci/agent.Dockerfile
  - ci/agent-entrypoint.sh
  - ci/plugins.txt
  - ci/docker-compose.yml
  - ci/.env.example
  - ci/jcasc/jenkins.yaml
  - .gitignore
autonomous: true
requirements: [CI-01, CI-07]
user_setup:
  - service: github
    why: "BUMP stage pushes the manifest commit to main via HTTPS; a repo-scoped PAT is the only secret Jenkins cannot self-provision"
    env_vars:
      - name: GITHUB_TOKEN
        source: "GitHub -> Settings -> Developer settings -> Personal access tokens -> Fine-grained -> repo erolclk1/DevSecOpsPipeline -> Contents: Read and write"
    dashboard_config: []
must_haves:
  truths:
    - "Jenkins controller boots fully configured from ci/jcasc/jenkins.yaml with no setup wizard"
    - "All plugins in ci/plugins.txt are installed (baked into the controller image, pinned versions)"
    - "A docker-builder agent is connected and can reach the host Docker daemon via the mounted socket"
    - "A demoapp-pipeline job is seeded from JCasC pointing at the repo-root Jenkinsfile"
    - "GitHub token and admin credentials come from ci/.env via env interpolation, never committed"
  artifacts:
    - path: "ci/controller.Dockerfile"
      provides: "Jenkins 2.555.3-lts-jdk21 with plugins baked + wizard disabled + CASC path"
      contains: "jenkins/jenkins:2.555.3-lts-jdk21"
    - path: "ci/plugins.txt"
      provides: "Pinned plugin list (CI-07)"
      contains: "configuration-as-code:"
    - path: "ci/docker-compose.yml"
      provides: "controller + docker-builder agent; socket on agent only"
      contains: "/var/run/docker.sock"
    - path: "ci/jcasc/jenkins.yaml"
      provides: "JCasC: security, credentials, agent node, job-dsl seed job"
      contains: "demoapp-pipeline"
  key_links:
    - from: "ci/docker-compose.yml (agent)"
      to: "host Docker daemon"
      via: "bind mount /var/run/docker.sock"
      pattern: "/var/run/docker.sock:/var/run/docker.sock"
    - from: "ci/jcasc/jenkins.yaml (job-dsl)"
      to: "Jenkinsfile"
      via: "cpsScm scriptPath('Jenkinsfile')"
      pattern: "scriptPath..Jenkinsfile"
    - from: "ci/jcasc/jenkins.yaml (credentials)"
      to: "ci/.env"
      via: "env interpolation GITHUB_TOKEN"
      pattern: "GITHUB_TOKEN"
---

<objective>
Provision a fully reproducible Jenkins from Configuration-as-Code: a custom controller image with pinned plugins and the setup wizard disabled, a socket-mount `docker-builder` agent that runs docker/trivy/yq/git against the host daemon, and a JCasC file that defines security, the GitHub credential, the agent node, and a job-dsl seed job for `demoapp-pipeline`. No UI wizard, no manual plugin install.

Purpose: Satisfies CI-01 (JCasC controller) and CI-07 (pinned plugins.txt). Everything the pipeline (Plan 03) needs — the agent label, the credential id, the seed job — is created here.
Output: ci/controller.Dockerfile, ci/agent.Dockerfile, ci/agent-entrypoint.sh, ci/plugins.txt, ci/docker-compose.yml, ci/.env.example, ci/jcasc/jenkins.yaml, updated .gitignore.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/ROADMAP.md
@.planning/phases/04-jenkins-ci/04-RESEARCH.md
@.planning/phases/04-jenkins-ci/04-VALIDATION.md

<interfaces>
<!-- Contracts other plans depend on. Fix these names exactly. -->

Container names (used by smoke-test.sh / verify-jcasc.sh from Plan 01):
- controller: `jenkins`   (compose service name AND container_name)
- agent:      `jenkins-agent` (compose service name AND container_name)

Agent label consumed by Jenkinsfile (Plan 03): `docker-builder`
Seed job name consumed by scenario-1/2.sh (Plan 01): `demoapp-pipeline`
Build parameter consumed by scenarios: `DOCKERFILE` (default `Dockerfile`; fixed run uses `Dockerfile.fixed`)
Credential id consumed by Jenkinsfile BUMP stage (Plan 03): `github-token` (Secret text = the PAT)
Jenkinsfile location (Plan 03): repo root -> seed job scriptPath('Jenkinsfile')
Repo: https://github.com/erolclk1/DevSecOpsPipeline.git , branch main

Pinned Jenkins image (CLAUDE.md / STACK.md): jenkins/jenkins:2.555.3-lts-jdk21
Trivy v0.72.0, yq v4.45.1 -- baked into the agent image.
Registry: build/push/scan via localhost:5001 on the host daemon (Docker auto-trusts localhost).

Socket path decision (RESEARCH.md Pitfall 1 -- TOP RISK): target is Windows/WSL2 Rancher Desktop.
Default the agent mount to /var/run/docker.sock:/var/run/docker.sock. The macOS-only ~/.rd/docker.sock
is WRONG for the target. If `docker exec jenkins-agent docker info` fails at boot, the mount path is the cause.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Controller + agent Dockerfiles, entrypoint, and pinned plugins.txt</name>
  <files>ci/controller.Dockerfile, ci/agent.Dockerfile, ci/agent-entrypoint.sh, ci/plugins.txt</files>
  <read_first>
    - .planning/phases/04-jenkins-ci/04-RESEARCH.md (Pattern 1, Standard Stack plugin table, agent.Dockerfile example)
    - app/build.sh (registry/tool expectations the agent must satisfy)
    - Makefile (lines 160-188: current jenkins-start scaffold being replaced -- do NOT mount socket on controller)
  </read_first>
  <action>
    Create `ci/plugins.txt` -- one plugin per line as `short-name:VERSION`, NO `:latest`, NO bare names. Include exactly these 12 short names: `configuration-as-code`, `workflow-aggregator`, `job-dsl`, `pipeline-stage-view`, `docker-workflow`, `credentials`, `credentials-binding`, `git`, `git-client`, `timestamper`, `ansicolor`, `matrix-auth`. Pin each to a concrete version compatible with Jenkins 2.555.3 -- obtain current versions at execute time (WebFetch `https://plugins.jenkins.io/<name>/` or, after first boot, `docker exec jenkins jenkins-plugin-cli --list`). Do NOT copy stale version numbers blindly; if unsure, boot the controller once and freeze the resolved versions back into this file.

    Create `ci/controller.Dockerfile`:
    ```dockerfile
    FROM jenkins/jenkins:2.555.3-lts-jdk21
    # Disable the setup wizard (CI-01: no UI wizard)
    ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
    # JCasC config location (file mounted read-only by docker-compose)
    ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml
    COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
    RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt
    ```

    Create `ci/agent.Dockerfile` -- bakes docker CLI + Trivy v0.72.0 + yq v4.45.1 + git:
    ```dockerfile
    FROM jenkins/inbound-agent:latest-jdk21
    USER root
    RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates docker.io git \
     && curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin v0.72.0 \
     && curl -sfL https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_amd64 -o /usr/local/bin/yq \
     && chmod +x /usr/local/bin/yq \
     && rm -rf /var/lib/apt/lists/*
    COPY agent-entrypoint.sh /usr/local/bin/agent-entrypoint.sh
    RUN chmod +x /usr/local/bin/agent-entrypoint.sh
    ENTRYPOINT ["/usr/local/bin/agent-entrypoint.sh"]
    ```
    (At execute time confirm the trivy install.sh accepts the `v0.72.0` tag arg; if the target arch is arm64, change the yq asset to `yq_linux_arm64`.)

    Create `ci/agent-entrypoint.sh` -- auto-connects the inbound agent by fetching its JNLP secret with admin creds (no manual secret paste, fully reproducible):
    ```bash
    #!/usr/bin/env bash
    set -euo pipefail
    : "${JENKINS_URL:?}"; : "${JENKINS_AGENT_NAME:=docker-builder}"
    : "${JENKINS_ADMIN_USER:?}"; : "${JENKINS_ADMIN_PASSWORD:?}"
    echo "Waiting for controller at ${JENKINS_URL} ..."
    until curl -sf -o /dev/null "${JENKINS_URL}/login"; do sleep 3; done
    SECRET=""
    for i in $(seq 1 30); do
      SECRET=$(curl -sf -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
        "${JENKINS_URL}/computer/${JENKINS_AGENT_NAME}/slave-agent.jnlp" \
        | sed -n 's/.*<argument>\([a-f0-9]\{64\}\)<\/argument>.*/\1/p' | head -1) || true
      [ -n "${SECRET}" ] && break
      sleep 3
    done
    [ -n "${SECRET}" ] || { echo "Failed to obtain agent secret for ${JENKINS_AGENT_NAME}"; exit 1; }
    exec jenkins-agent -url "${JENKINS_URL}" -secret "${SECRET}" -name "${JENKINS_AGENT_NAME}" -workDir /home/jenkins/agent
    ```
  </action>
  <verify>
    <automated>test -f ci/controller.Dockerfile && test -f ci/agent.Dockerfile && test -f ci/plugins.txt && bash -n ci/agent-entrypoint.sh && grep -q 'jenkins/jenkins:2.555.3-lts-jdk21' ci/controller.Dockerfile && grep -q 'runSetupWizard=false' ci/controller.Dockerfile && grep -q 'v0.72.0' ci/agent.Dockerfile && ! grep -q ':latest' ci/plugins.txt && grep -q 'configuration-as-code:' ci/plugins.txt</automated>
  </verify>
  <acceptance_criteria>
    - `grep -q 'jenkins/jenkins:2.555.3-lts-jdk21' ci/controller.Dockerfile` succeeds
    - `grep -q 'runSetupWizard=false' ci/controller.Dockerfile` succeeds
    - `grep -q 'jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt' ci/controller.Dockerfile` succeeds
    - `ci/plugins.txt` contains all 12 short names, each followed by `:` and a version; `! grep -q ':latest' ci/plugins.txt` succeeds
    - `grep -q 'v0.72.0' ci/agent.Dockerfile` and `grep -q 'yq' ci/agent.Dockerfile` succeed
    - `grep -q 'slave-agent.jnlp' ci/agent-entrypoint.sh` succeeds (secret auto-fetch)
    - `bash -n ci/agent-entrypoint.sh` parses clean
  </acceptance_criteria>
  <done>Controller image bakes pinned plugins + disables wizard; agent image bundles docker/trivy/yq/git and auto-connects via fetched JNLP secret.</done>
</task>

<task type="auto">
  <name>Task 2: docker-compose.yml + .env.example + .gitignore</name>
  <files>ci/docker-compose.yml, ci/.env.example, .gitignore</files>
  <read_first>
    - .planning/phases/04-jenkins-ci/04-RESEARCH.md (Pattern 2 compose shape; Pitfall 1 socket path; Pitfall 5 GitHub auth)
    - .gitignore (current: node_modules/, .env.phase2 -- must add ci/.env)
    - Makefile (JENKINS_PORT 8080, container naming conventions)
  </read_first>
  <action>
    Create `ci/docker-compose.yml`. Socket is mounted on the AGENT ONLY (never the controller). Exact shape:
    ```yaml
    services:
      jenkins:
        build: { context: ., dockerfile: controller.Dockerfile }
        container_name: jenkins
        ports: ["8080:8080", "50000:50000"]
        environment:
          - CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml
          - TZ=UTC
        env_file: [.env]
        volumes:
          - jenkins_home:/var/jenkins_home
          - ./jcasc/jenkins.yaml:/var/jenkins_home/casc.yaml:ro
          # NO docker socket on the controller
      agent:
        build: { context: ., dockerfile: agent.Dockerfile }
        container_name: jenkins-agent
        depends_on: [jenkins]
        environment:
          - JENKINS_URL=http://jenkins:8080
          - JENKINS_AGENT_NAME=docker-builder
          - TZ=UTC
        env_file: [.env]
        volumes:
          - /var/run/docker.sock:/var/run/docker.sock   # WSL2 default; see RESEARCH Pitfall 1
          - trivy_cache:/home/jenkins/.trivy-cache
          - agent_work:/home/jenkins/agent
    volumes:
      jenkins_home: {}
      trivy_cache: {}
      agent_work: {}
    ```

    Create `ci/.env.example` (documented, committed) with placeholders -- agent-entrypoint and JCasC read these:
    ```
    # Copy to ci/.env and fill in. ci/.env is gitignored.
    JENKINS_ADMIN_USER=admin
    JENKINS_ADMIN_PASSWORD=changeme
    # GitHub fine-grained PAT with Contents: Read/Write on erolclk1/DevSecOpsPipeline
    GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
    GIT_USER=erolclk1
    ```

    Update `.gitignore` -- append a line `ci/.env` (keep existing `node_modules/` and `.env.phase2`). Do NOT ignore `ci/.env.example`.
  </action>
  <verify>
    <automated>test -f ci/docker-compose.yml && test -f ci/.env.example && grep -q '/var/run/docker.sock:/var/run/docker.sock' ci/docker-compose.yml && grep -q 'container_name: jenkins-agent' ci/docker-compose.yml && grep -q '^ci/.env$' .gitignore && grep -q 'GITHUB_TOKEN' ci/.env.example</automated>
  </verify>
  <acceptance_criteria>
    - `grep -q '/var/run/docker.sock:/var/run/docker.sock' ci/docker-compose.yml` succeeds (socket on agent)
    - The controller `jenkins` service block contains NO `docker.sock` mount (manually confirm socket appears only under the `agent` service)
    - `grep -q 'container_name: jenkins' ci/docker-compose.yml` and `grep -q 'container_name: jenkins-agent' ci/docker-compose.yml` succeed
    - `grep -q 'JENKINS_AGENT_NAME=docker-builder' ci/docker-compose.yml` succeeds
    - `grep -q './jcasc/jenkins.yaml:/var/jenkins_home/casc.yaml:ro' ci/docker-compose.yml` succeeds
    - `grep -q '^ci/.env$' .gitignore` succeeds; `ci/.env.example` is NOT ignored
    - `ci/.env.example` contains `GITHUB_TOKEN`, `JENKINS_ADMIN_USER`, `JENKINS_ADMIN_PASSWORD`
  </acceptance_criteria>
  <done>Compose brings up controller (no socket) + agent (socket mounted, trivy cache volume); secrets sourced from gitignored ci/.env with a committed example.</done>
</task>

<task type="auto">
  <name>Task 3: JCasC jenkins.yaml (security, credential, agent node, seed job)</name>
  <files>ci/jcasc/jenkins.yaml</files>
  <read_first>
    - .planning/phases/04-jenkins-ci/04-RESEARCH.md (Pattern 1 env interpolation, Pattern 3 job-dsl seed job)
    - bootstrap/argocd/application.yaml (repoURL + branch that the seed job must also target)
    - ci/.env.example (env var names JENKINS_ADMIN_USER/PASSWORD/GITHUB_TOKEN this file interpolates)
  </read_first>
  <action>
    Create `ci/jcasc/jenkins.yaml`. Use `${VAR}` env interpolation for all secrets (values come from ci/.env at container start). Exact structure:

    ```yaml
    jenkins:
      systemMessage: "DevSecOps thesis pipeline — provisioned entirely by JCasC"
      numExecutors: 0          # controller runs no builds; all work goes to the agent
      securityRealm:
        local:
          allowsSignup: false
          users:
            - id: "${JENKINS_ADMIN_USER}"
              password: "${JENKINS_ADMIN_PASSWORD}"
      authorizationStrategy:
        loggedInUsersCanDoAnything:
          allowAnonymousRead: false
      nodes:
        - permanent:
            name: "docker-builder"
            labelString: "docker-builder"
            remoteFS: "/home/jenkins/agent"
            retentionStrategy: "always"
            launcher:
              inbound:
                workDirSettings:
                  disabled: false
                  workDirPath: "/home/jenkins/agent"

    credentials:
      system:
        domainCredentials:
          - credentials:
              - string:
                  scope: GLOBAL
                  id: "github-token"
                  secret: "${GITHUB_TOKEN}"
                  description: "GitHub PAT for BUMP stage push to main"

    unclassified:
      location:
        url: "http://localhost:8080/"

    jobs:
      - script: |
          pipelineJob('demoapp-pipeline') {
            parameters {
              stringParam('DOCKERFILE', 'Dockerfile', 'Dockerfile to build: Dockerfile (vulnerable) or Dockerfile.fixed (patched)')
            }
            definition {
              cpsScm {
                scm {
                  git {
                    remote { url('https://github.com/erolclk1/DevSecOpsPipeline.git') }
                    branch('main')
                  }
                }
                scriptPath('Jenkinsfile')
              }
            }
          }
    ```

    Notes for the executor:
    - `numExecutors: 0` forces every stage onto the `docker-builder` agent (which has the docker socket + trivy + yq). The Jenkinsfile (Plan 03) declares `agent { label 'docker-builder' }`.
    - The `github-token` credential id and the `DOCKERFILE` parameter name are contracts consumed by Plan 03 and Plan 01 scenario scripts — do not rename.
    - Validate the JCasC syntax after first boot with `docker exec jenkins sh -c 'ls -l $CASC_JENKINS_CONFIG'` and by confirming the dashboard shows the `demoapp-pipeline` job.
  </action>
  <verify>
    <automated>test -f ci/jcasc/jenkins.yaml && grep -q 'demoapp-pipeline' ci/jcasc/jenkins.yaml && grep -q "scriptPath('Jenkinsfile')" ci/jcasc/jenkins.yaml && grep -q 'id: "github-token"' ci/jcasc/jenkins.yaml && grep -q 'labelString: "docker-builder"' ci/jcasc/jenkins.yaml && grep -q "stringParam('DOCKERFILE'" ci/jcasc/jenkins.yaml && python3 -c "import yaml,sys; yaml.safe_load(open('ci/jcasc/jenkins.yaml'))"</automated>
  </verify>
  <acceptance_criteria>
    - `ci/jcasc/jenkins.yaml` parses as valid YAML (`python3 -c "import yaml; yaml.safe_load(open('ci/jcasc/jenkins.yaml'))"` exits 0)
    - `grep -q 'demoapp-pipeline' ci/jcasc/jenkins.yaml` succeeds (seed job)
    - `grep -q "scriptPath('Jenkinsfile')" ci/jcasc/jenkins.yaml` succeeds (repo-root Jenkinsfile)
    - `grep -q 'id: "github-token"' ci/jcasc/jenkins.yaml` succeeds (credential contract)
    - `grep -q 'labelString: "docker-builder"' ci/jcasc/jenkins.yaml` succeeds (agent node)
    - `grep -q "stringParam('DOCKERFILE'" ci/jcasc/jenkins.yaml` succeeds (build parameter contract)
    - `grep -q '${GITHUB_TOKEN}' ci/jcasc/jenkins.yaml` and `${JENKINS_ADMIN_PASSWORD}` present (env interpolation, no plaintext secret)
  </acceptance_criteria>
  <done>JCasC defines admin login, github-token credential, the docker-builder inbound node, and a parameterized demoapp-pipeline seed job pointing at the repo-root Jenkinsfile.</done>
</task>

</tasks>

<verification>
- `docker compose -f ci/docker-compose.yml config` parses without error (run at execute time).
- `docker compose -f ci/docker-compose.yml up -d --build` then `bash ci/smoke-test.sh` (from Plan 01) exits 0: controller reachable on 8080, agent reaches docker.
- `bash ci/tests/verify-jcasc.sh` (from Plan 01) exits 0: no initialAdminPassword file, plugins match plugins.txt, `demoapp-pipeline` job present.
</verification>

<success_criteria>
- CI-01: Jenkins boots with all config via JCasC — no setup wizard; `demoapp-pipeline` job exists without any UI clicks.
- CI-07: `ci/plugins.txt` pins every plugin with an explicit version (no `:latest`); installed set matches the file.
- Agent connects automatically and `docker exec jenkins-agent docker info` succeeds against the host daemon.
- No secret is committed: `ci/.env` is gitignored; only `ci/.env.example` (placeholders) is tracked.
</success_criteria>

<output>
After completion, create `.planning/phases/04-jenkins-ci/04-jenkins-provision-SUMMARY.md`.
</output>
