# Roadmap — DevSecOps Pipeline Thesis

**Defined:** 2026-07-02
**Granularity:** Standard (6 phases)
**Coverage:** 37/37 v1 requirements mapped

---

## Phases

- [x] **Phase 1: Bootstrap** — Registry + k3s cluster + host-to-VM name resolution verified end-to-end (completed 2026-07-09)
- [ ] **Phase 2: Vulnerable App** — Demo app with deterministic vulnerabilities built, pushed, and deployed via raw `kubectl apply`
- [ ] **Phase 3: GitOps** — ArgoCD auto-syncs from Git; Kyverno enforces admission policies; no direct cluster writes
- [ ] **Phase 4: Jenkins CI** — JCasC-driven pipeline automates build → Trivy scan → push → manifest bump without human involvement
- [ ] **Phase 5: Runtime Security** — Falco detects all three attack patterns; Falcosidekick persists alerts to file and webui
- [ ] **Phase 6: Demo Polish** — Three scenarios run from a Makefile; full stack reproduces on a clean machine from docs alone

---

## Milestone Map

| Milestone | Phases | Name | Outcome |
|-----------|--------|------|---------|
| A | 1 – 2 | Pipeline Foundation | Cluster runs, local registry reachable from both host and VM, vulnerable app deployed and reachable |
| B | 3 – 4 | Security Controls Wired | Every code push triggers full automated security pipeline: Trivy blocks bad builds, ArgoCD deploys good ones, Kyverno enforces policy |
| C | 5 – 6 | Demo Ready | Runtime attacks trigger named Falco alerts; all three thesis scenarios reproducible via single Makefile command |

---

## Phase Dependencies

```
Phase 1 ──► Phase 2 ──► Phase 3 ──► Phase 4 ──► Phase 5 ──► Phase 6
```

- **Phase 1 → Phase 2:** Cluster and registry must be reachable before deploying any app image
- **Phase 2 → Phase 3:** A running, manually deployed app must exist before ArgoCD has anything to sync
- **Phase 3 → Phase 4:** The GitOps path (ArgoCD watching the overlay) must exist for Jenkins manifest bumps to have a visible effect
- **Phase 4 → Phase 5:** A stable, CI-deployed app is required before runtime detection demos have a reliable target
- **Phase 5 → Phase 6:** All attack scenarios must work before they can be scripted into runbooks and Makefile targets

All phases are strictly sequential. No parallelism is possible or useful at single-developer scale.

---

## Phase Details

---

## Phase 1: Bootstrap

**Goal:** Prove that a container pushed from the host reaches a running pod in the k3s cluster — registry name resolution verified end-to-end — before any application code exists.

**Depends on:** Nothing (first phase)

**Requirements covered:** INFRA-01, INFRA-02, INFRA-03

**Estimated effort:** 1–2 days

**Tasks:**
1. Install Rancher Desktop 1.23.1; verify `kubectl get nodes` returns a single `Ready` node and `docker version` reports the bundled engine
2. Start `registry:2` container on host port 5000: `docker run -d --restart=always -p 5000:5000 --name registry registry:2`
3. Author `~/.rd/k3s/registries.yaml` with `host.rancher-desktop.internal:5000` mirror and `insecure_skip_verify: true`; restart Rancher Desktop to reload containerd config
4. Verify registry reachable from host: `curl http://host.rancher-desktop.internal:5000/v2/` → `{}`
5. Push a smoke-test image and verify the cluster can pull it: `kubectl run pull-test --image=host.rancher-desktop.internal:5000/hello:smoke --restart=Never`; pod must reach `Running`
6. Verify registry reachable from inside the cluster: `kubectl run curl-test --rm -it --image=curlimages/curl -- curl http://host.rancher-desktop.internal:5000/v2/` → `{}`
7. Commit the working `registries.yaml` to `cluster/registries.yaml` with the exact syntax that passed — this is the Phase 1 artefact

**Success Criteria** (what must be TRUE):
1. `kubectl get nodes` shows exactly one node in `Ready` state
2. `curl http://host.rancher-desktop.internal:5000/v2/` from the host returns `{}`
3. A pod referencing `host.rancher-desktop.internal:5000/hello:smoke` reaches `Running` state without `ImagePullBackOff`
4. `curl http://host.rancher-desktop.internal:5000/v2/` from inside a cluster pod returns `{}`

**Key Risks:**
1. **Pitfall 2 — Registry hostname not resolvable inside Lima VM:** `host.rancher-desktop.internal` may map to `host.lima.internal` on some Apple Silicon versions of RD 1.23.1. Test both; use whichever resolves. Never hardcode an IP — DHCP breaks it on every roam.
2. **Pitfall 13 — Docker Desktop conflict:** Running Docker Desktop alongside Rancher Desktop fights for the `docker` CLI symlink and `kubectl` context. Fully uninstall Docker Desktop before starting, or set `docker context use rancher-desktop` explicitly.
3. **Open question must be answered here:** Document the exact `registries.yaml` hostname and k3s minor version (from `kubectl version`) before moving to Phase 2.

**Plans:** 2/2 plans complete

Plans:
- [ ] 01-PLAN-registry-setup.md — Rancher Desktop + registry:2 + registries.yaml + host-side verification
- [ ] 01-PLAN-pull-verification.md — Smoke image push, pod pull test, in-cluster registry curl

---

## Phase 2: Vulnerable App

**Goal:** Build a demo REST API with known, deterministic vulnerabilities that Trivy reliably flags and attack scripts will reliably trigger — validating the end-to-end demo story before any pipeline automation is added.

**Depends on:** Phase 1

**Requirements covered:** APP-01, APP-02, APP-03, APP-04

**Estimated effort:** 1–2 days

**Tasks:**
1. Scaffold Node.js 22 REST API (`app/`) with two deliberately vulnerable endpoints: `/sqli?user=` (string-concatenated SQL query using `mysql` client, no parameterization) and `/cmd?input=` (`child_process.exec` with unvalidated input); comment each vulnerable line with an `// INTENTIONALLY VULNERABLE` marker
2. Write `app/Dockerfile` using a pinned outdated base (`node:14.0.0-alpine` or equivalent old digest); omit `USER` directive so container runs as root; add a `.dockerignore` excluding `node_modules`, `.git`, `.env*`
3. Run `trivy image --severity HIGH,CRITICAL` locally against the built image; confirm at least one CRITICAL finding and record the CVE ID — if Trivy reports clean, the base image is wrong
4. Write `deploy/base/` Kustomize base manifests: `Namespace`, `Deployment` (image placeholder), `Service` (NodePort for host access)
5. Write `deploy/overlays/local/demoapp-patch.yaml` with the initial image tag; deploy with `kubectl apply -k deploy/overlays/local/`
6. Verify the app is reachable from the host and running as root: `kubectl exec <pod> -- whoami` returns `root`; `curl "http://localhost:<nodeport>/sqli?user=1 OR 1=1"` returns data leak or SQL error confirming exploitability
7. Manually smoke-test the command injection endpoint: `curl "http://localhost:<nodeport>/cmd?input=id"` returns the container user identity

**Success Criteria** (what must be TRUE):
1. `trivy image --severity HIGH,CRITICAL --exit-code 1 host.rancher-desktop.internal:5000/demoapp:<tag>` exits non-zero with at least one CRITICAL CVE reported
2. Pod is in `Running` state with `kubectl exec <pod> -- whoami` returning `root`
3. `curl "http://localhost:<nodeport>/sqli?user=' OR '1'='1"` returns a response that proves SQL injection is possible (data leak or SQL error, not a 500 with no output)
4. `curl "http://localhost:<nodeport>/cmd?input=id"` returns the container user identity in the response body

**Key Risks:**
1. **Pitfall 11 — Vulnerability design:** A base image with many CVEs does not guarantee the app path exercises them at runtime. The SQL injection must use explicit string concatenation (not `mysql2` parameterized queries) and the command injection must use `child_process.exec` (not `execFile`). Test each attack manually before moving to Phase 5.
2. **Pitfall 20 — Missing .dockerignore:** Without `.dockerignore`, the build context includes `.git`, `node_modules`, and any `.env` files. Add it before the first `docker build`.
3. **Node.js vs Python decision:** This phase requires committing to one runtime. Node.js 22 is recommended (smaller Alpine surface, well-understood SQLi attack path). Document the choice in PROJECT.md Key Decisions before writing code.

**Plans:** TBD

**UI hint**: yes

---

## Phase 3: GitOps

**Goal:** Prove that a Git commit is the only mechanism that changes cluster state — ArgoCD syncs the app automatically and Kyverno rejects non-compliant manifests at admission time.

**Depends on:** Phase 2

**Requirements covered:** GITOPS-01, GITOPS-02, GITOPS-03, GITOPS-04, GITOPS-05, GITOPS-06

**Estimated effort:** 2 days

**Tasks:**
1. Install ArgoCD v3.4.4 via Helm chart 10.1.0 in `argocd` namespace with non-HA values (`redis-ha.enabled=false`, `controller.replicas=1`, `server.replicas=1`); verify UI accessible via `kubectl port-forward svc/argocd-server -n argocd 8443:443`
2. Create `bootstrap/argocd/application.yaml` — an ArgoCD `Application` CR pointing `repoURL` at the mono-repo, `path: deploy/overlays/local/`, with `automated: {prune: true, selfHeal: true}`; apply to `argocd` namespace
3. Confirm Kustomize overlay is structured so a tag change is exactly one line in `demoapp-patch.yaml`; test: edit the tag in Git and push — ArgoCD must sync and replace the pod without any `kubectl apply`
4. Install Kyverno (latest stable) via Helm; install 4 community policies from the Kyverno policy library: `disallow-latest-tag`, `restrict-image-registries` (allow only `host.rancher-desktop.internal:5000`), `disallow-privileged-containers`, `require-resource-limits`
5. Demonstrate self-heal: `kubectl edit deployment demoapp -n demoapp` and change the image tag to something wrong — ArgoCD must revert the change within the sync interval
6. Demonstrate Kyverno admission blocking: apply a test manifest with `image: demoapp:latest` — verify it is denied and `kubectl get policyreport -n demoapp` shows the violation
7. Investigate and configure `ignoreDifferences` if ArgoCD flaps `Synced/OutOfSync` due to cluster-managed fields (managed fields, annotations from Kyverno)

**Success Criteria** (what must be TRUE):
1. ArgoCD UI shows Application `Synced` and `Healthy` after initial sync
2. Pushing a one-line tag change to `demoapp-patch.yaml` in Git causes the running pod to be replaced with the new image — no `kubectl apply` command is run by the operator
3. `kubectl edit deployment demoapp -n demoapp` changing the image tag is reverted by ArgoCD within the sync interval (self-heal confirmed)
4. Applying a manifest with `image: demoapp:latest` is blocked at admission; `kubectl get policyreport -n demoapp` shows the `disallow-latest-tag` violation
5. `kubectl get policyreport -n demoapp` shows admission results from all 4 Kyverno policies

**Key Risks:**
1. **Pitfall 7 — ArgoCD sync loop:** Kyverno mutating webhooks or server-side-apply managed fields cause continuous `Synced → OutOfSync` flapping. Resolve with `ignoreDifferences` in the Application spec for cluster-owned fields; check whether ArgoCD v3.4 enables ServerSideApply by default (open question — resolve in this phase).
2. **Pitfall 8 — ImagePullBackOff after sync:** If the Kustomize patch references a tag that was never pushed, pods fail silently with `ErrImagePull` while ArgoCD reports `Synced`. Always verify the tag exists in the registry before committing: `curl http://host.rancher-desktop.internal:5000/v2/demoapp/tags/list`.
3. **Pitfall 9 — False-degraded health status:** ArgoCD may mark the app `Degraded` during slow pod startup. Add `initialDelaySeconds: 15` to the readiness probe in the base manifest to avoid cascading health-check failures.

**Plans:** TBD

**UI hint**: yes

---

## Phase 4: Jenkins CI

**Goal:** Automate the full build → scan → push → manifest-bump cycle so a Git push triggers Jenkins, Trivy either blocks or passes, and ArgoCD deploys the result — no human ever runs `kubectl` or `docker push` manually again.

**Depends on:** Phase 3

**Requirements covered:** CI-01, CI-02, CI-03, CI-04, CI-05, CI-06, CI-07

**Estimated effort:** 2–3 days

**Tasks:**
1. Write `ci/docker-compose.yml` for Jenkins controller + Docker-capable agent; mount `~/.rd/docker.sock` (Rancher Desktop socket path, not `/var/run/docker.sock`) only on the agent container; controller volume is `jenkins_home` only
2. Write `ci/jcasc/jenkins.yaml` (JCasC): global config, credentials (registry, Git token via env var `${REGISTRY_CRED}`), agent label `docker-builder`, seed job pointing at `Jenkinsfile`
3. Write `ci/plugins.txt` with explicit versions for all required plugins (configuration-as-code, workflow-aggregator, pipeline-stage-view, docker-workflow, credentials-binding, git, timestamper, ansicolor, matrix-auth, job-dsl); no `:latest` tags
4. Author `Jenkinsfile` with 4 declarative stages: BUILD (`docker build` tagged with `git rev-parse --short HEAD`, never `:latest`), SCAN (Trivy shell step — `--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --no-progress --cache-dir $JENKINS_HOME/.trivy-cache`; also archive CycloneDX SBOM via second invocation with `--format cyclonedx`), PUSH (only executes if SCAN passes), BUMP (`yq` updates `deploy/overlays/local/demoapp-patch.yaml` image tag, commits, and pushes to Git — no `kubectl apply`)
5. Configure `TRIVY_DB_REPOSITORY` env var in JCasC pointing at `public.ecr.aws/aquasecurity/trivy-db` as fallback; persist Trivy cache at `$JENKINS_HOME/.trivy-cache` across builds
6. Write `ci/jenkins-reset.sh` — wipes `jenkins_home` volume and re-provisions from JCasC; required for reproducibility in thesis demo
7. Run Scenario 1 smoke test: build with vulnerable Dockerfile → confirm SCAN stage fails, pipeline goes red, no new tag appears in registry
8. Run Scenario 2 smoke test: build with fixed Dockerfile → all 4 stages green, new SHA tag in registry, `demoapp-patch.yaml` updated in Git, pod version replaced via ArgoCD

**Success Criteria** (what must be TRUE):
1. Jenkins boots with all pipeline jobs pre-configured via JCasC — no UI wizard steps required; `diff plugins.txt <(docker exec jenkins jenkins-plugin-cli --list)` returns empty
2. Build with vulnerable image: pipeline fails at SCAN stage; `curl http://host.rancher-desktop.internal:5000/v2/demoapp/tags/list` shows no new tag — the image was NOT pushed
3. Build with fixed image: all 4 stages green; new `<sha>` tag visible in registry; `demoapp-patch.yaml` updated in Git with the new tag; ArgoCD syncs and pod restarts with the new version
4. CycloneDX SBOM JSON archived as a Jenkins build artefact for every passing build
5. `ci/jenkins-reset.sh` reproduces a fully configured Jenkins instance from JCasC without manual UI interaction

**Key Risks:**
1. **Pitfall 1 — Wrong Docker socket path:** Rancher Desktop exposes Docker at `~/.rd/docker.sock`, not `/var/run/docker.sock`. Mounting the wrong path causes `docker: command not found` in pipeline stages. Verify the correct socket path in the compose file before first boot.
2. **Pitfall 5 — First green run takes 4–6 hours:** Every pipeline failure requires a container restart cycle. Mitigate: use JCasC from day 1, iterate the Jenkinsfile with the `Replay` button (5 s feedback vs 90 s SCM poll), keep `jenkins-reset.sh` ready for clean reprovisioning.
3. **Pitfall 10 — Trivy DB download failures:** GHCR rate limits or offline network break scans silently (exit 0, 0 CVEs). Configure persistent cache volume and `TRIVY_DB_REPOSITORY` fallback before first run; smoke-test with `vulnerables/web-dvwa` — if Trivy reports clean on it, the DB is broken.

**Plans:** TBD

---

## Phase 5: Runtime Security

**Goal:** Prove that attacks against the running demo application trigger named Falco alerts within 30 seconds, with events logged to a persistent file via Falcosidekick.

**Depends on:** Phase 4

**Requirements covered:** FALCO-01, FALCO-02, FALCO-03, FALCO-04, FALCO-05, ATK-01, ATK-02, ATK-03, ATK-04

**Estimated effort:** 2 days

**Tasks:**
1. Install Falco 0.44.1 via Helm chart 9.1.0: `--set driver.kind=modern_ebpf --set tty=true --set falcosidekick.enabled=true --set falcosidekick.webui.enabled=true --set collectors.kubernetes.enabled=true`; verify pod `Running` and `kubectl logs -f` shows "driver: modern_ebpf" and "Falco initialized"
2. Configure Falcosidekick file output: add a hostPath volume at `/var/log/falco/` mapped to `logs/falco.log` on the host; confirm Falcosidekick webui accessible via `kubectl port-forward svc/falcosidekick-ui -n falco 2802`
3. Write 5 custom rules in `falco/rules/custom-rules.yaml`, all scoped with `k8s.ns.name = "demoapp"` (prevents false positives from `kube-system`/`argocd`):
   - `reverse-shell`: detects `nc -e`, `bash -i`, `/dev/tcp` redirection; conditions layer `proc.name` + `fd.type=ipv4` + `fd.sip != "127.0.0.1"`
   - `shell-from-webapp`: detects `bash`/`sh` spawned as child of `node`/`python` process
   - `read-sensitive-file`: detects opens of `/etc/shadow`, `/etc/sudoers`, `.ssh/*`
   - `package-management-in-container`: detects `apk`, `apt`, `pip install` at runtime
   - `contact-k8s-api`: detects app pod hitting `kubernetes.default.svc`
4. Validate rule syntax: confirm Falco startup logs show all 5 custom rules loaded without parse errors
5. Write `attacks/sqli.py`: deterministic SQL injection against `http://localhost:<nodeport>/sqli`; hard-coded target, exit 0 on successful data extraction, includes safety comment documenting ethical constraint
6. Write `attacks/reverse_shell.sh`: triggers the `/cmd` command injection endpoint to open reverse shell to `localhost:4444`; hard-coded target; fires `reverse-shell` and `shell-from-webapp` Falco rules
7. Write `attacks/privilege_probe.sh`: execs into the demo pod (`kubectl exec`) and runs `cat /etc/shadow`, `id`, `whoami`, `apk add curl`; fires `read-sensitive-file` and `package-management-in-container` rules; all targets hard-coded to localhost/cluster IP
8. Run all three scripts sequentially; verify Falcosidekick webui shows ≥3 distinct named alerts within 30 seconds and `logs/falco.log` contains the persisted events

**Success Criteria** (what must be TRUE):
1. Falco DaemonSet pod is `Running`; `kubectl logs -f <falco-pod> -n falco` shows "driver: modern_ebpf" and "Falco initialized" — no `CrashLoopBackOff`
2. All 5 custom rules load cleanly — no parse errors in Falco startup logs
3. Running `attacks/reverse_shell.sh` triggers at least the `reverse-shell` and `shell-from-webapp` rules; both alerts appear in the Falcosidekick webui within 30 seconds
4. Running `attacks/privilege_probe.sh` triggers at least the `read-sensitive-file` and `package-management-in-container` rules
5. After pod restart, `logs/falco.log` on the host still contains all previously emitted alerts (persistent storage verified)
6. Normal ArgoCD and Jenkins operations generate zero Falco alerts (namespace scoping verified by observing `kubectl logs -f <falco-pod>` during a full pipeline run)

**Key Risks:**
1. **Pitfall 3 — Falco CrashLoopBackOff:** The Falco Helm chart default `driver.kind=auto` may still attempt `kmod` first on some chart versions, causing immediate crash on Rancher Desktop (no kernel headers). Pin `driver.kind=modern_ebpf` explicitly. Pre-check: `uname -r ≥ 5.8` and `/sys/kernel/btf/vmlinux` must exist in the VM.
2. **Pitfall 6 — Custom rules too noisy:** Rules based only on `proc.name` fire on every `kubectl exec` debug session. Use layered conditions (`proc.name` + `fd.sip` + `container.image.repository`), scope all rules to `k8s.ns.name = "demoapp"`, and add TTY exceptions for interactive debug sessions.
3. **Pitfall 16 — Falcosidekick webui unreachable during demo:** If the port-forward drops, the audience sees nothing. Configure file output as the primary sink (always works regardless of network); treat webui as secondary. Verify both before every demo rehearsal.

**Plans:** TBD

---

## Phase 6: Demo Polish

**Goal:** Package all three demo scenarios into one-command Makefile targets so the complete thesis demonstration reproduces on a clean machine in under one hour from docs alone.

**Depends on:** Phase 5

**Requirements covered:** INFRA-04, APP-05, DEMO-01, DEMO-02, DEMO-03, DOCS-01, DOCS-02, DOCS-03, DOCS-04, DOCS-05

**Estimated effort:** 1–2 days

**Tasks:**
1. Write `Makefile` with targets: `up` (full bootstrap — registry, cluster config, ArgoCD, Kyverno, Falco, Jenkins), `down` (full teardown), `demo-1` (blocked build scenario), `demo-2` (successful deploy scenario), `demo-3` (live attack scenario), `reset-jenkins` (wipe and re-provision Jenkins from JCasC)
2. Write `docs/setup.md`: step-by-step bootstrap guide for a fresh macOS install — Rancher Desktop prerequisites, exact `registries.yaml` syntax (use the Phase 1 confirmed version), resource limit recommendations, and troubleshooting steps for the top 3 failure modes
3. Write `docs/scenarios.md`: three demo runbooks with exact commands, expected terminal output snippets, timing notes (e.g., "wait 30 s for ArgoCD sync"), and thesis slide cues for each scenario
4. Write `docs/architecture.md`: component diagram showing the three security layers (shift-left Trivy in Jenkins, GitOps Kyverno admission control, runtime Falco detection), data flow (Git → Jenkins → Registry → ArgoCD → Cluster → Falco), and network topology (host / Rancher Desktop VM / registry / cluster boundaries)
5. Write `README.md` with quickstart section (5 commands to demo), prerequisites list, and link to thesis context
6. Write `app/README.md` documenting the SQL injection endpoint (OWASP A03:2021 Injection) and command injection endpoint (OWASP A03:2021 Injection / OS Command) with the exact vulnerable code line referenced
7. Rehearse all three scenarios on a clean `make down && make up` cycle; record any timing or ordering issues; fix before freeze
8. Verify peak RAM stays under 10 GB: run `kubectl top pods -A --sort-by=memory` and `docker stats --no-stream` during the full `demo-3` run (highest memory scenario)

**Success Criteria** (what must be TRUE):
1. `make up` on a machine with only Rancher Desktop installed provisions the full stack in under 15 minutes and exits 0
2. `make demo-1` produces a Jenkins red build at the SCAN stage with Trivy CVE output; `curl http://host.rancher-desktop.internal:5000/v2/demoapp/tags/list` confirms no new image tag was pushed
3. `make demo-2` produces a green 4-stage Jenkins pipeline; `demoapp-patch.yaml` is updated in Git; the new pod version is visible in the ArgoCD UI
4. `make demo-3` runs all three attack scripts; Falcosidekick webui shows ≥3 named alerts within 30 seconds; `logs/falco.log` contains the persisted events
5. `docs/scenarios.md` contains exact commands and expected output for all three scenarios — a dry-run confirms no commands fail
6. Peak RAM during the full demo run stays below 10 GB

**Key Risks:**
1. **Pitfall 4 — RAM blowout during demo:** Running `demo-2` (Jenkins build + Trivy) concurrently with `demo-3` (attack simulation + Falco event spike) pushes total RAM above 12 GB and triggers macOS swap, causing `CrashLoopBackOff` cascades. Makefile targets must serialize workloads; note in runbook that demos are sequential, not concurrent.
2. **Pitfall 11 — Live-demo failure due to cold caches:** A fresh `make up` leaves Trivy DB uncached and ArgoCD syncs slow. Add a `make demo-warmup` target that runs a no-op build and forces a Trivy DB download before the audience arrives; document in `docs/scenarios.md`.
3. **Pitfall 18 — Timezone mismatch:** Host timestamps and Falco log timestamps disagree by hours if not aligned. Set `TZ=UTC` in Jenkins, Falco, and demo app container env vars; document the UTC requirement in `docs/setup.md`.

**Plans:** TBD

**UI hint**: yes

---

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Bootstrap | 0/2 | Complete    | 2026-07-09 |
| 2. Vulnerable App | 0/0 | Not started | — |
| 3. GitOps | 0/0 | Not started | — |
| 4. Jenkins CI | 0/0 | Not started | — |
| 5. Runtime Security | 0/0 | Not started | — |
| 6. Demo Polish | 0/0 | Not started | — |

---

## Requirement Coverage

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 1: Bootstrap | Pending |
| INFRA-02 | Phase 1: Bootstrap | Pending |
| INFRA-03 | Phase 1: Bootstrap | Pending |
| INFRA-04 | Phase 6: Demo Polish | Pending |
| APP-01 | Phase 2: Vulnerable App | Pending |
| APP-02 | Phase 2: Vulnerable App | Pending |
| APP-03 | Phase 2: Vulnerable App | Pending |
| APP-04 | Phase 2: Vulnerable App | Pending |
| APP-05 | Phase 6: Demo Polish | Pending |
| CI-01 | Phase 4: Jenkins CI | Pending |
| CI-02 | Phase 4: Jenkins CI | Pending |
| CI-03 | Phase 4: Jenkins CI | Pending |
| CI-04 | Phase 4: Jenkins CI | Pending |
| CI-05 | Phase 4: Jenkins CI | Pending |
| CI-06 | Phase 4: Jenkins CI | Pending |
| CI-07 | Phase 4: Jenkins CI | Pending |
| GITOPS-01 | Phase 3: GitOps | Pending |
| GITOPS-02 | Phase 3: GitOps | Pending |
| GITOPS-03 | Phase 3: GitOps | Pending |
| GITOPS-04 | Phase 3: GitOps | Pending |
| GITOPS-05 | Phase 3: GitOps | Pending |
| GITOPS-06 | Phase 3: GitOps | Pending |
| FALCO-01 | Phase 5: Runtime Security | Pending |
| FALCO-02 | Phase 5: Runtime Security | Pending |
| FALCO-03 | Phase 5: Runtime Security | Pending |
| FALCO-04 | Phase 5: Runtime Security | Pending |
| FALCO-05 | Phase 5: Runtime Security | Pending |
| ATK-01 | Phase 5: Runtime Security | Pending |
| ATK-02 | Phase 5: Runtime Security | Pending |
| ATK-03 | Phase 5: Runtime Security | Pending |
| ATK-04 | Phase 5: Runtime Security | Pending |
| DEMO-01 | Phase 6: Demo Polish | Pending |
| DEMO-02 | Phase 6: Demo Polish | Pending |
| DEMO-03 | Phase 6: Demo Polish | Pending |
| DOCS-01 | Phase 6: Demo Polish | Pending |
| DOCS-02 | Phase 6: Demo Polish | Pending |
| DOCS-03 | Phase 6: Demo Polish | Pending |
| DOCS-04 | Phase 6: Demo Polish | Pending |
| DOCS-05 | Phase 6: Demo Polish | Pending |

**Coverage:** 37/37 v1 requirements mapped. 0 orphaned.

---

*Roadmap defined: 2026-07-02*
*Last updated: 2026-07-02 after initial roadmap creation*
