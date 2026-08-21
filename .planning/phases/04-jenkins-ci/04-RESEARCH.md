# Phase 4: Jenkins CI - Research

**Researched:** 2026-08-14
**Domain:** Jenkins declarative pipeline + Trivy shift-left scanning + GitOps manifest bump on Rancher Desktop (Windows/WSL2)
**Confidence:** HIGH on tools/patterns; MEDIUM on Windows/WSL2 Docker-socket and registry-networking specifics (must be verified empirically on the target machine)

## Summary

Phase 4 automates what `app/build.sh` (Phase 2) already does by hand — build → Trivy scan → push → manifest bump — inside a reproducible, JCasC-provisioned Jenkins. The GitOps boundary from Phase 3 is already live: ArgoCD (`bootstrap/argocd/application.yaml`) watches `deploy/overlays/local/` on `main` of `github.com/erolclk1/DevSecOpsPipeline.git` with auto-sync + self-heal, and Kyverno enforces `disallow-latest-tag` (Enforce) plus three Audit policies. Jenkins' only job is: fail fast on CVEs, and on success push an image and commit a one-line tag change to `demoapp-patch.yaml`. Jenkins must never touch the cluster.

The single biggest execution risk is **not** the pipeline logic — it is the Docker-socket path and registry networking on the Windows/WSL2 target. Every existing artifact (registries.yaml, insecure-registry.start, demoapp-patch.yaml, build.sh) proves the working registry topology is `localhost:5001` for push and `host.rancher-desktop.internal:5001` for pull. The phase task text and the current Makefile scaffold both hardcode `~/.rd/docker.sock`, which is the **macOS/lima** socket path — it does not exist on the Windows/WSL2 target machine (CLAUDE.md declares Windows WSL2 as the pipeline machine). This contradiction must be resolved before first boot or Jenkins will fail with `docker: command not found` / socket-not-found on every stage.

**Primary recommendation:** Use a **socket-mount agent** (not DinD): a custom `docker-builder` agent image bundling docker-cli + Trivy v0.72.0 + yq v4 + git, with the host Docker socket mounted **only on the agent**. Because `docker build`/`docker push` execute against the host daemon via the mounted socket, push to `localhost:5001` works exactly as `build.sh` proves (Docker treats `localhost` as insecure automatically). Write `host.rancher-desktop.internal:5001` into the manifest. Provision everything via JCasC + a job-dsl seed job from day one, and guard the BUMP commit with `[skip ci]` to prevent an infinite build loop.

## Project Constraints (from CLAUDE.md)

These are non-negotiable directives. Plans MUST comply; research does not recommend anything that contradicts them.

1. **Jenkins MUST NOT `kubectl apply`.** Jenkins commits only to `deploy/overlays/local/`. ArgoCD is the sole cluster mutator. This separation IS the thesis demonstration.
2. **Image tags are always git short SHA — never `:latest`.** Enforced by Kyverno `disallow-latest-tag` (Enforce mode). A `:latest` push would be admission-rejected at deploy.
3. **Registry hostname is `host.rancher-desktop.internal:5001`** in manifests (never `localhost:5001`, never a hardcoded IP). Push from host via `localhost:5001` (HTTP, treated as insecure by Docker automatically).
4. **Port is 5001, not 5000.** Rancher Desktop binds 5000 internally. Note: `REQUIREMENTS.md` CI-04 text still says `:5000` — that is stale; the working artifacts (registries.yaml, demoapp-patch.yaml, build.sh, insecure-registry.start) all use **5001**. Use 5001.
5. **Trivy is a CLI shell step, not the Jenkins plugin** (project decision, STATE.md).
6. **JCasC from day one.** No UI wizard state. Config lives in git.
7. **dockerd ignores `registries.yaml`** — insecure-registry trust for `host.rancher-desktop.internal:5001` is applied inside the VM via `cluster/insecure-registry.start`. This is already in place from Phase 1.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CI-01 | Jenkins LTS 2.555.3 (JDK 21) as Docker container, JCasC from `ci/jcasc/jenkins.yaml` | Custom controller Dockerfile FROM `jenkins/jenkins:2.555.3-lts-jdk21` + `CASC_JENKINS_CONFIG` + setup-wizard disabled (see Architecture Pattern 1) |
| CI-02 | BUILD stage: `docker build` tagged with git short SHA (never `:latest`) | `git rev-parse --short HEAD`; build runs on host daemon via mounted socket (Pattern 2) |
| CI-03 | SCAN stage: Trivy `--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1`; fail → no push | Verified flag set (Code Examples); `node:14.21.3-alpine` base guarantees CRITICAL findings |
| CI-04 | PUSH stage: push to registry only after Trivy passes; SHA tag | Stage ordering + `when`/exit-gate; push to `localhost:5001` on host daemon |
| CI-05 | BUMP stage: `yq` updates `demoapp-patch.yaml`, commit + push to Git (never `kubectl apply`) | yq v4 in-place edit + git push with PAT credential + `[skip ci]` loop guard (Pattern 3, Pitfall 4) |
| CI-06 | Trivy CycloneDX SBOM archived as build artefact per run | Second Trivy invocation `--format cyclonedx`; `archiveArtifacts` in `post` (Code Examples) |
| CI-07 | Plugin list pinned in `plugins.txt` with explicit versions; installed via JCasC/plugins.txt | `jenkins-plugin-cli -f plugins.txt` baked into controller image (Pattern 1); no `:latest` |
</phase_requirements>

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Jenkins LTS | `2.555.3-lts-jdk21` | CI controller | Pinned by thesis; Java 21 mandatory since 2.555.1 |
| Trivy | v0.72.0 | Vuln scan + SBOM | CLI shell step (project decision); static binary, no daemon |
| yq (mikefarah) | v4.x (v4.45.1 verified on dev machine) | In-place YAML edit of image tag | Deterministic single-line manifest bump; matches CI-05 |
| Docker Engine | 27.x (bundled by RD) | build/push via host socket | Provided by Rancher Desktop; buildx available |
| git | 2.x | clone + BUMP commit/push | Present in agent image |

### Supporting (Jenkins plugins — CI-07)
Pin explicit versions in `ci/plugins.txt`. Verify current versions at plan/execute time on `plugins.jenkins.io` (plugin versions move weekly; do NOT copy stale numbers from training data).

| Plugin | Purpose |
|--------|---------|
| `configuration-as-code` | JCasC engine (current line: `2117.vXXXX`, requires Jenkins ≥ 2.541.1 — satisfied) |
| `workflow-aggregator` | Declarative + scripted pipeline engine |
| `job-dsl` | Seed job that creates the pipeline job from JCasC |
| `pipeline-stage-view` | Visual stage pass/block for thesis screenshots |
| `docker-workflow` | `docker.build` / `docker.image` DSL (optional if using `sh 'docker ...'`) |
| `credentials` + `credentials-binding` | GitHub PAT (and optional registry cred) via `withCredentials` |
| `git` + `git-client` | Git SCM clone |
| `timestamper` | Log timestamps — correlate scan output with Falco events later |
| `ansicolor` | Colored Trivy severity output in console |
| `matrix-auth` | JCasC-friendly authorization strategy |

**Explicitly NOT installed:** Trivy Jenkins plugin (use CLI), Blue Ocean (heavy — 16 GB budget).

### Version verification (run before writing plugins.txt / stack table)
```bash
# On the Windows target (Git Bash) or dev machine:
trivy --version                       # expect 0.72.0
yq --version                          # expect v4.x
# Plugin versions — check each at https://plugins.jenkins.io/<name>/
# or, from a booted controller: docker exec jenkins jenkins-plugin-cli --list
```

**Installation (agent image tools):**
```dockerfile
# ci/agent.Dockerfile — docker-builder agent
FROM jenkins/inbound-agent:latest-jdk21
USER root
RUN apt-get update && apt-get install -y curl docker.io git \
 && curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin v0.72.0 \
 && curl -sfL https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_amd64 -o /usr/local/bin/yq \
 && chmod +x /usr/local/bin/yq
```
(Pin exact versions; verify the install.sh tag argument is accepted by the current script at execute time.)

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Socket-mount agent | Docker-in-Docker (DinD) sidecar | DinD needs privileged + a separate daemon + its own insecure-registries config; socket-mount reuses the host daemon that already trusts the registry. Socket-mount wins. |
| yq for tag edit | `sed`/`kustomize edit set image` | `kustomize edit set image` is cleaner but changes file shape; `yq -i` is a minimal one-line diff (matches GITOPS-03 intent). `sed` is brittle. Prefer yq; kustomize edit acceptable. |
| Custom controller Dockerfile for plugins | `--set` env `JENKINS_PLUGIN_INFO` | Custom Dockerfile with `jenkins-plugin-cli -f plugins.txt` is the reproducible standard and satisfies CI-07's "installed via plugins.txt". |

## Architecture Patterns

### Recommended file layout (new files this phase)
```
ci/
├── docker-compose.yml      # controller + docker-builder agent; socket on agent ONLY
├── controller.Dockerfile   # FROM jenkins/jenkins:2.555.3-lts-jdk21 + plugins.txt
├── agent.Dockerfile        # docker-cli + trivy 0.72.0 + yq v4 + git
├── plugins.txt             # pinned plugin versions (CI-07)
├── jcasc/
│   └── jenkins.yaml        # JCasC: global, credentials, agent, seed job
├── jenkins-reset.sh        # wipe jenkins_home volume + re-provision
└── .env.example            # GITHUB_TOKEN, GIT_USER, etc. (real .env gitignored)
Jenkinsfile                 # repo root (per task 2/4 & success criteria) — 4 stages
```
Keep `Jenkinsfile` at repo root and set the seed job `scriptPath('Jenkinsfile')`. (If placed under `ci/`, set `scriptPath('ci/Jenkinsfile')` — be consistent with the seed job.)

### Pattern 1: JCasC-provisioned controller, no wizard
- Custom controller image bakes plugins: `RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt`.
- Disable wizard: `ENV JAVA_OPTS=-Djenkins.install.runSetupWizard=false`.
- Point JCasC: `ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml` (or a read-only mounted path). The current Makefile uses `/var/jenkins_home/casc.yaml`; mounting `ci/jcasc/jenkins.yaml` read-only is cleaner and keeps config in git.
- Credentials come from **env-var interpolation**, never committed: JCasC supports `${GITHUB_TOKEN}` syntax. Provide via docker-compose `env_file: .env` (gitignored — add to `.gitignore`).

### Pattern 2: Socket-mount agent (docker commands run on host daemon)
```yaml
# ci/docker-compose.yml (essential shape)
services:
  jenkins:
    build: { context: ., dockerfile: controller.Dockerfile }
    ports: ["8080:8080", "50000:50000"]
    environment:
      - CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml
      - TZ=UTC
    env_file: [.env]                 # GITHUB_TOKEN etc.
    volumes:
      - jenkins_home:/var/jenkins_home
      # NO docker socket on controller
  agent:
    build: { context: ., dockerfile: agent.Dockerfile }
    environment: [ "TZ=UTC" ]
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock   # ⚠ Windows/WSL2 path — VERIFY (see Pitfall 1)
      - trivy_cache:/home/jenkins/.trivy-cache
volumes: { jenkins_home: {}, trivy_cache: {} }
```
Because `docker build`/`docker push` hit the **host** daemon, `localhost:5001` resolves to the host registry (as in `build.sh`). Docker auto-trusts `localhost`/`127.0.0.1` as insecure — no extra config needed for push.

### Pattern 3: Seed job via job-dsl in JCasC
```yaml
jobs:
  - script: |
      pipelineJob('demoapp-pipeline') {
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

### Anti-Patterns to Avoid
- **Socket on the controller.** Task 1 and Pitfall 2 (research) require socket on the agent only; keep `jenkins_home` clean. The current Makefile `jenkins-start` mounts the socket on the controller and runs no agent — this is the scaffold to REPLACE with docker-compose.
- **Pushing `host.rancher-desktop.internal:5001` FROM the agent container over the network.** Don't. Run docker against the host socket and push to `localhost:5001`; only the *manifest* uses the cluster hostname.
- **`kubectl` anywhere in the Jenkinsfile.** Forbidden (CLAUDE.md rule 1).
- **`|| true` around Trivy.** Kills the gate (Pitfall 6, research).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| YAML image-tag edit | regex/sed surgery | `yq -i` (or `kustomize edit set image`) | Preserves structure, one-line diff, no accidental reformat |
| CVE gating | parsing Trivy JSON + threshold logic | `trivy --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed` | Native exit-code contract is the block mechanism |
| SBOM generation | custom dependency walker | `trivy image --format cyclonedx` | Standardized CycloneDX; free with Trivy |
| Docker build isolation | DinD + privileged daemon | mount host socket on agent | Reuses daemon that already trusts the registry |
| Jenkins config | manual UI wizard | JCasC + job-dsl seed | Reproducible; required by CI-01/CI-07 and `jenkins-reset.sh` |
| Plugin install | manual UI plugin manager | `jenkins-plugin-cli -f plugins.txt` | Pinned + reproducible (CI-07) |

**Key insight:** Phase 2's `app/build.sh` is a working reference implementation of BUILD→SCAN→PUSH. The Jenkinsfile is essentially that script re-expressed as declarative stages plus a BUMP stage. Do not reinvent the flow — port it.

## Common Pitfalls

### Pitfall 1: Wrong Docker socket path on Windows/WSL2 (TOP RISK)
**What goes wrong:** Every docker stage fails (socket not found / `docker: command not found`).
**Why it happens:** `~/.rd/docker.sock` is the **macOS/lima** socket path. The phase task text and the current Makefile hardcode it, but CLAUDE.md/STATE declare the pipeline machine is **Windows with the WSL2 backend**. On Windows/WSL2 with the dockerd (moby) engine, the socket the container should mount is `/var/run/docker.sock` (the WSL2-bridged daemon socket), not `~/.rd/docker.sock`.
**How to avoid:** Before first boot, on the Windows target run: `docker context ls`, `echo $DOCKER_HOST` (in the WSL2 distro / Git Bash), and confirm `/var/run/docker.sock` exists inside WSL2. Mount whichever the daemon actually exposes. Treat `/var/run/docker.sock:/var/run/docker.sock` as the working default for WSL2; keep `~/.rd/docker.sock` only if the machine turns out to be macOS.
**Warning signs:** Agent boots but BUILD stage errors immediately; `docker info` inside the agent fails.
**Confidence:** MEDIUM — the macOS/lima path `~/.rd/docker.sock` is HIGH-confidence documented; the exact Windows/WSL2 mount must be confirmed empirically on the target (cannot be probed from the macOS dev machine).

### Pitfall 2: Manifest-bump commit re-triggers the pipeline (infinite loop)
**What goes wrong:** BUMP pushes to `main`; SCM polling/webhook sees a new commit and rebuilds, which bumps again, forever.
**Why it happens:** Jenkins watches the same repo/branch it commits to.
**How to avoid:** Append `[skip ci]`/`[ci skip]` to the BUMP commit message AND/OR restrict the trigger so only changes under `app/` build (path filter), not `deploy/`. Verify the SCM trigger honors the skip token, or gate in the Jenkinsfile by inspecting the last commit message.
**Warning signs:** Back-to-back builds with only `demoapp-patch.yaml` changing.

### Pitfall 3: Trivy DB download failure → silent 0-CVE pass
**What goes wrong:** DB fails to download; Trivy exits 0 with zero findings; a vulnerable image passes the gate.
**Why it happens:** Registry rate limits / offline network; empty cache on fresh `jenkins-reset.sh`.
**How to avoid:** Persist cache (`--cache-dir` on a named volume, e.g. `/home/jenkins/.trivy-cache`). The current Trivy default DB order is `mirror.gcr.io/aquasec` then `ghcr.io/aquasecurity` (mirror.gcr.io already dodges most GHCR rate limits). Configure `TRIVY_DB_REPOSITORY` fallback only if needed — **note that setting it OVERRIDES the defaults**, so include the defaults too if you set it (e.g. `mirror.gcr.io/aquasec/trivy-db,ghcr.io/aquasecurity/trivy-db,public.ecr.aws/aquasecurity/trivy-db`). Smoke-test with a known-vulnerable image; if it reports clean, the DB is broken. **This resolves Open Question 8:** default primary is `mirror.gcr.io/aquasec/trivy-db`; the ECR fallback `public.ecr.aws/aquasecurity/trivy-db` is still valid.
**Warning signs:** SCAN passes on `node:14.21.3-alpine` (which must show CRITICALs).

### Pitfall 4: First green run takes 4–6 hours
**What goes wrong:** Slow iteration because every failure needs a container/config cycle.
**How to avoid:** JCasC from day 1; pin plugins; iterate the Jenkinsfile with the **Replay** button (≈5 s vs 90 s SCM poll); keep `ci/jenkins-reset.sh` ready. Author the Jenkinsfile against the proven `build.sh` logic to minimize surprises.

### Pitfall 5: GitHub push auth from inside CI
**What goes wrong:** BUMP stage can't push (`main` is HTTPS, no credentials in container).
**How to avoid:** Store a GitHub PAT as a Jenkins credential (via JCasC env interpolation → `withCredentials`), and push via `https://<user>:<token>@github.com/erolclk1/DevSecOpsPipeline.git`. Set `git config user.email/name` in the stage. The local `registry:2` has **no authentication**, so a registry credential is optional — the mandatory secret is the GitHub token.

### Pitfall 6: SBOM only on passing builds vs thesis evidence
**What goes wrong:** SCAN fails and stops the pipeline before SBOM is generated, so the blocked-build scenario (DEMO-01) has no SBOM/report artefact.
**How to avoid:** Generate the CycloneDX SBOM (and a JSON CVE report) **before** the failing `--exit-code 1` gate call, then `archiveArtifacts` in `post { always { ... } }` with `allowEmptyArchive: true`. Success criterion 4 requires SBOM "for every passing build"; generating earlier also gives evidence for the blocked scenario.

## Code Examples

### SCAN gate + SBOM (verified flags, Trivy v0.72.0)
```groovy
// Jenkinsfile — SCAN stage. Runs on agent (label 'docker-builder'), docker via host socket.
stage('SCAN') {
  steps {
    // 1) SBOM + report first, so artefacts exist even if the gate fails
    sh '''
      trivy image --format cyclonedx --output demoapp-sbom.json \
        --cache-dir "$TRIVY_CACHE" localhost:5001/demoapp:${GIT_SHA}
      trivy image --severity HIGH,CRITICAL --format json --output trivy-report.json \
        --cache-dir "$TRIVY_CACHE" localhost:5001/demoapp:${GIT_SHA} || true
    '''
    // 2) The gate — non-zero exit fails the stage (block mechanism)
    sh '''
      trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 \
        --scanners vuln --no-progress --cache-dir "$TRIVY_CACHE" \
        localhost:5001/demoapp:${GIT_SHA}
    '''
  }
}
```
Source: Trivy DB config + container-image docs (trivy.dev, verified 2026-08-14); flags match STACK.md.
Note: CycloneDX generation does not require `--scanners vuln`; the gate call keeps it for clarity. Trivy resolves the image via the host Docker daemon (socket) or by pulling from the registry — both work here.

### BUMP stage (yq + git push, loop-guarded)
```groovy
stage('BUMP') {
  steps {
    withCredentials([string(credentialsId: 'github-token', variable: 'GH_TOKEN')]) {
      sh '''
        yq -i '.spec.template.spec.containers[0].image =
          "host.rancher-desktop.internal:5001/demoapp:'"$GIT_SHA"'"' \
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
```
Note: manifest gets the **cluster** hostname `host.rancher-desktop.internal:5001` (matches existing `demoapp-patch.yaml` and Kyverno `restrict-image-registries`); push used `localhost:5001`.

### GIT_SHA + BUILD
```groovy
environment { GIT_SHA = "" ; TRIVY_CACHE = "/home/jenkins/.trivy-cache" }
stage('BUILD') {
  steps {
    script { env.GIT_SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim() }
    sh 'docker build -t localhost:5001/demoapp:${GIT_SHA} app/'
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Trivy DB default `ghcr.io/aquasecurity` | Primary `mirror.gcr.io/aquasec`, then GHCR | Trivy ~0.50+ | GHCR rate limits largely avoided out of the box; explicit fallback less critical |
| Jenkins any JDK | JDK 21 mandatory | LTS 2.555.1 | Must use `-jdk21` image (already pinned) |
| DinD for build agents | Socket-mount / rootless / Kaniko | ongoing | Socket-mount is simplest here and reuses host registry trust |

**Deprecated/outdated:**
- `~/.rd/docker.sock` as a universal path — it is macOS/lima-only; wrong for the Windows/WSL2 target.
- CI-04 requirement text saying port `5000` — superseded by 5001 in all working artifacts.

## Open Questions

1. **Exact Docker socket mount on the Windows/WSL2 target**
   - What we know: `~/.rd/docker.sock` is macOS/lima; WSL2 daemon typically exposes `/var/run/docker.sock`.
   - What's unclear: precise path/context on this specific RD 1.23.1 Windows install (cannot probe from the macOS dev machine).
   - Recommendation: run `docker context ls` + confirm `/var/run/docker.sock` in WSL2 before first boot; default the compose mount to `/var/run/docker.sock`.

2. **Registry reachability from the agent for Trivy pull**
   - What we know: docker build/push use the host daemon (localhost:5001 OK). Trivy inside the agent can use the socket or pull from a registry.
   - What's unclear: if Trivy pulls by network from inside the agent, it must reach the registry (use `host.rancher-desktop.internal:5001` or the socket/`--image-src docker`).
   - Recommendation: prefer scanning via the Docker daemon (socket) with `--image-src docker` so no in-container network path to the registry is required.

3. **SCM trigger honoring `[skip ci]`**
   - What we know: `[skip ci]` is the conventional loop guard.
   - What's unclear: whether the chosen trigger (poll vs webhook) respects it out of the box.
   - Recommendation: combine `[skip ci]` with a path filter (build only on `app/**` changes).

## Environment Availability

> The pipeline runs on the **Windows/WSL2 target machine**; this research ran on the **macOS dev machine (code only)**. The table below reflects the dev machine plus what the target requires. The target must be probed on-site.

| Dependency | Required By | Available (dev/macOS) | Version | Fallback |
|------------|-------------|-----------------------|---------|----------|
| Docker Engine | BUILD/PUSH | ✓ (dev) | 27.4.0 | RD-bundled on target |
| docker compose | controller+agent orchestration | ✓ (dev) | v2.31.0 | `docker run` (current Makefile) |
| yq (v4) | BUMP | ✓ (dev) | v4.45.1 | bake into agent image |
| git | clone/BUMP | ✓ (dev) | 2.50.1 | — |
| Trivy v0.72.0 | SCAN/SBOM | ✗ (dev) | — | bake into agent image (required) |
| Rancher Desktop 1.23.1 (WSL2) | whole pipeline | ✗ (dev) | — | none — target machine only |
| `/var/run/docker.sock` (WSL2) | agent socket mount | unverifiable from dev | — | see Open Question 1 |
| GitHub PAT | BUMP push | not present | — | create repo-scoped PAT, store as Jenkins credential |

**Missing dependencies with no fallback:** Rancher Desktop + working Docker socket on the Windows target — must exist before Phase 4 (satisfied by Phase 1). GitHub PAT with push access to `main` — must be created.
**Missing with fallback:** Trivy, yq — baked into the agent image at build time.

## Validation Architecture

> nyquist_validation is enabled (config.json). Phase 4 validation is inherently end-to-end (pipeline behavior), so most checks are integration/smoke, not unit.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Shell-based smoke tests (Scenario 1 & 2) + `curl` registry assertions; no unit framework in repo |
| Config file | none — see Wave 0 |
| Quick run command | `git rev-parse --short HEAD` then `curl -sf http://localhost:5001/v2/demoapp/tags/list` |
| Full suite command | Trigger `demoapp-pipeline` (vulnerable then fixed) + assert registry tags + `git log` bump |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CI-01 | Boots via JCasC, no wizard, plugins match | smoke | `docker exec jenkins jenkins-plugin-cli --list` vs `plugins.txt` | ❌ Wave 0 (`ci/tests/verify-jcasc.sh`) |
| CI-02 | Image tagged with short SHA | smoke | inspect built tag == `git rev-parse --short HEAD` | ❌ Wave 0 |
| CI-03 | Vulnerable image fails SCAN, no push | integration | run Scenario 1; assert stage red + `tags/list` unchanged | ❌ Wave 0 (`ci/tests/scenario-1.sh`) |
| CI-04 | Push only after pass; SHA tag present | integration | Scenario 2; `curl .../demoapp/tags/list` shows new SHA | ❌ Wave 0 |
| CI-05 | Manifest bumped + committed, no kubectl | integration | `git log -1 demoapp-patch.yaml` shows bump; ArgoCD syncs | ❌ Wave 0 (`ci/tests/scenario-2.sh`) |
| CI-06 | CycloneDX SBOM archived per run | smoke | check Jenkins build artefact `demoapp-sbom.json` exists | ❌ Wave 0 |
| CI-07 | plugins.txt pinned, reproducible | smoke | `diff <(sort plugins.txt) <(...--list \| sort)` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** lint/parse — `docker compose config`, JCasC dry validate, `groovy`/Jenkinsfile `Replay`.
- **Per wave merge:** Scenario 1 (blocked) + registry tag assertion.
- **Phase gate:** Scenario 1 + Scenario 2 both green (vulnerable blocks, fixed deploys via ArgoCD) before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `ci/tests/scenario-1.sh` — vulnerable build blocks at SCAN; asserts no new registry tag (CI-03)
- [ ] `ci/tests/scenario-2.sh` — fixed build all-green; asserts SHA tag + `demoapp-patch.yaml` bump + ArgoCD sync (CI-04, CI-05)
- [ ] `ci/tests/verify-jcasc.sh` — plugins.txt parity + no-wizard boot (CI-01, CI-07)
- [ ] A "fixed" Dockerfile/base (e.g. `node:22-alpine`) is needed for Scenario 2 — current `app/Dockerfile` is `node:14.21.3-alpine` (intentionally vulnerable). Plan must provide the fixed variant (branch or build-arg).

## Empirical Findings (confirmed on Windows/WSL2 target, 2026-08-21)

The following were verified during Phase 4 execution on the actual Windows/Rancher Desktop 1.23.1 target:

### Resolved: Docker socket path (Open Question 1)
**`/var/run/docker.sock` confirmed.** The research recommendation was correct. Compose mount for the agent is `/var/run/docker.sock:/var/run/docker.sock`. `~/.rd/docker.sock` does not exist on the Windows/WSL2 target — it is macOS/lima only.

### New finding: Dynamic GID fixup required
The socket's GID at container runtime differs from what is baked into the agent image (the GID is set by the Windows/WSL2 daemon and changes between restarts). `ci/agent-entrypoint.sh` was updated to detect the actual GID at startup via `stat -c '%g' /var/run/docker.sock` and re-create the `docker` group with that GID before exec-ing the agent process. Without this, `docker build` fails with a permission denied error even though the socket is mounted.

### New finding: Docker static binary required
The `docker.io` Debian apt package caused issues on this target. The agent image was updated to download the Docker static binary directly (`docker-28.3.3.tgz` from `download.docker.com`). This is more reliable and version-pinned.

### Resolved: Trivy `--image-src docker` (Open Question 2)
Using `--image-src docker` in all three Trivy calls (SBOM + report + gate) works correctly — Trivy accesses the locally-built image through the host daemon socket. No in-container network path to the registry is needed.

### New finding: Jenkins CSRF crumb required for POST API calls
Simple `curl -X POST` to `/job/<name>/buildWithParameters` returns HTTP 403 on Jenkins 2.555.3. Scripts must:
1. `GET /crumbIssuer/api/json` with a cookie jar to obtain `crumbRequestField` + `crumb`
2. POST with `Cookie:` (via `-b cookie_jar`) and `${CRUMB_FIELD}: ${CRUMB}` header

Both `ci/tests/scenario-1.sh` and `ci/tests/scenario-2.sh` were updated accordingly.

### New finding: Queue item tracking needed in scenario-2.sh
The trigger response returns a `Location:` header pointing to the queued build's API URL. The script polls that URL until `"number"` appears, then tracks that specific build number to avoid `lastBuild` race conditions when the pipeline is busy.

### New finding: Separate package files for the fixed image
`app/Dockerfile.fixed` uses `package.fixed.json` and `package-lock.fixed.json` — separate from the vulnerable app's package files — renamed on COPY so `npm ci` works cleanly:
```dockerfile
COPY package.fixed.json ./package.json
COPY package-lock.fixed.json ./package-lock.json
RUN npm ci --omit=dev
```
Dependencies: `express@4.22.2`, `mysql@2.18.1` (no HIGH/CRITICAL npm CVEs).

### New finding: OS-layer CVEs in `node:22-alpine` — use `.trivyignore`
Even the "fixed" image based on `node:22-alpine` has 8 Alpine package CVEs (busybox, musl, libssl etc.) that have no upstream fix. These are NOT npm CVEs — the npm tree is clean. The Jenkinsfile SCAN gate now includes `--ignorefile .trivyignore`, and the `.trivyignore` file documents the 8 accepted CVE IDs. This is standard DevSecOps practice: document accepted risks, not suppress the tool.

### Resolved: `[skip ci]` loop guard (Open Question 3)
Confirmed working. BUMP commits (`ci: bump demoapp to <sha> [skip ci]`) do not re-trigger the pipeline. Git history shows the BUMP commits followed by silence — no infinite loop.

## Sources

### Primary (HIGH confidence)
- Trivy DB configuration — https://trivy.dev/latest/docs/configuration/db/ (default repo order, override behavior)
- Trivy container image target — https://trivy.dev/latest/docs/target/container_image/ (daemon vs registry, `--image-src`)
- Repo artifacts (ground truth): `app/build.sh`, `app/Dockerfile`, `cluster/registries.yaml`, `cluster/insecure-registry.start`, `deploy/overlays/local/demoapp-patch.yaml`, `bootstrap/argocd/application.yaml`, `bootstrap/kyverno/*.yaml`, `Makefile`
- `.planning/research/STACK.md`, `.planning/research/SUMMARY.md`, `.planning/research/PITFALLS.md` (prior verified research)

### Secondary (MEDIUM confidence)
- `plugins.jenkins.io/configuration-as-code` — current JCasC plugin line `2117.vXXXX`, requires Jenkins ≥ 2.541.1
- JCasC job-dsl seed-job pattern (established `pipelineJob`/`cpsScm` recipe)

### Tertiary (LOW confidence — verify on target)
- Windows/WSL2 Rancher Desktop Docker socket path (`/var/run/docker.sock` vs `~/.rd/docker.sock`) — WebFetch on RD docs returned 404/no answer; must confirm empirically on the target machine.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — versions pinned by thesis and cross-checked; plugin exact versions to confirm at execute time.
- Architecture / pipeline logic: HIGH — mirrors proven `build.sh`; GitOps boundary already live from Phase 3.
- Trivy flags + DB behavior: HIGH — verified against trivy.dev on 2026-08-14.
- Windows/WSL2 Docker socket + agent-registry networking: MEDIUM — must be verified on the Windows target (not reachable from macOS dev machine).

**Research date:** 2026-08-14
**Valid until:** 2026-09-13 (30 days; Jenkins plugin versions move faster — reverify plugins.txt at execute time)
