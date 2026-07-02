# Requirements: DevSecOps Pipeline — Cybersecurity Thesis

**Defined:** 2026-07-02  
**Core Value:** A demonstrable, locally runnable pipeline where vulnerable container images are automatically blocked, secure images are deployed via GitOps, and cyberattacks are detected in real time.

---

## v1 Requirements

### Infrastructure Bootstrap

- [ ] **INFRA-01**: Local Docker registry (`registry:2`) running on host and reachable from k3s cluster via `host.rancher-desktop.internal:5000`
- [ ] **INFRA-02**: k3s single-node cluster running via Rancher Desktop 1.23.1 with registry configured in `registries.yaml`
- [ ] **INFRA-03**: `kubectl get nodes` returns Ready; `curl` from inside cluster reaches local registry
- [ ] **INFRA-04**: One-command bootstrap script (`make up`) installs all cluster components from scratch

### Demo Application

- [ ] **APP-01**: Vulnerable REST API (Node.js 22 or Python 3.12) with SQL injection endpoint (string-concatenated query, no parameterisation)
- [ ] **APP-02**: Command injection endpoint (`os.system` / `child_process.exec` with unvalidated user input)
- [ ] **APP-03**: Dockerfile with deliberately outdated base image (pinned old digest) that guarantees Trivy HIGH/CRITICAL findings on every build
- [ ] **APP-04**: App initially runs as root in container (demonstrates Kyverno policy denial)
- [ ] **APP-05**: App has a README documenting each vulnerability with OWASP 2021 category reference

### CI Pipeline (Jenkins + Trivy)

- [ ] **CI-01**: Jenkins LTS 2.555.3 (JDK 21) running as Docker container with JCasC configuration loaded from `ci/jcasc/jenkins.yaml`
- [ ] **CI-02**: Jenkins pipeline has BUILD stage: `docker build` tagged with git short SHA (never `:latest`)
- [ ] **CI-03**: Jenkins pipeline has SCAN stage: Trivy `--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1`; pipeline fails and image is NOT pushed when CVEs found
- [ ] **CI-04**: Jenkins pipeline has PUSH stage: image pushed to `host.rancher-desktop.internal:5000/demoapp:<sha>` only after Trivy passes
- [ ] **CI-05**: Jenkins pipeline has BUMP stage: updates `deploy/overlays/local/demoapp-patch.yaml` image tag via `yq`, commits, and pushes to Git (never `kubectl apply`)
- [ ] **CI-06**: Trivy SBOM output (`--format cyclonedx`) archived as build artefact per run
- [ ] **CI-07**: Jenkins plugin list pinned in `plugins.txt` with explicit versions; plugins installed via JCasC `plugins.txt` (reproducible)

### GitOps Deployment (ArgoCD + Kyverno)

- [ ] **GITOPS-01**: ArgoCD v3.4.4 installed via Helm chart 10.1.0 in `argocd` namespace
- [ ] **GITOPS-02**: ArgoCD Application CR watches `deploy/overlays/local/` with auto-sync, self-heal, and prune enabled
- [ ] **GITOPS-03**: Kustomize overlay uses image patch (`demoapp-patch.yaml`) so CI manifest bump is a single YAML line change visible in `git diff`
- [ ] **GITOPS-04**: Kyverno installed with 4 policies: `disallow-latest-tag`, `restrict-image-registries`, `disallow-privileged-containers`, `require-resource-limits`
- [ ] **GITOPS-05**: ArgoCD self-heal demonstration: manual `kubectl edit` of image tag is reverted within the sync interval
- [ ] **GITOPS-06**: Kyverno PolicyReport CR shows admission decisions during demo

### Runtime Security (Falco)

- [ ] **FALCO-01**: Falco 0.44.1 deployed as DaemonSet with `driver.kind=modern_ebpf` (explicit, not `auto`)
- [ ] **FALCO-02**: Falcosidekick deployed with file output (`/var/log/falco/events.log` on host-mounted volume) and webui enabled
- [ ] **FALCO-03**: 5 custom Falco rules loaded from `falco/rules/`: reverse shell, shell-spawned-by-webapp, read-sensitive-file, package-management-in-container, contact-k8s-api
- [ ] **FALCO-04**: All custom rules scoped by `k8s.ns.name = "demoapp"` to prevent false positives from system namespaces
- [ ] **FALCO-05**: `kubectl logs -f` on Falco DaemonSet shows structured JSON alerts in real time during attack demos

### Attack Simulation

- [ ] **ATK-01**: `attacks/sqli.py` — SQL injection script that extracts data from demo app; deterministic, idempotent, only targets `localhost`
- [ ] **ATK-02**: `attacks/reverse_shell.sh` — triggers command injection endpoint to open reverse shell; fires Falco reverse-shell and shell-from-webapp rules
- [ ] **ATK-03**: `attacks/privilege_probe.sh` — `cat /etc/shadow`, `id`, `whoami`, `apk add curl` inside container; fires sensitive-file and package-management rules
- [ ] **ATK-04**: All attack scripts hard-code `localhost`/cluster IP and include a safety comment documenting the ethical constraint

### Demo Scenarios

- [ ] **DEMO-01**: Scenario 1 (Blocked Build): pipeline run with vulnerable image → Trivy fails → image NOT pushed → Jenkins shows red stage; screenshots and CVE report captured
- [ ] **DEMO-02**: Scenario 2 (Successful Deploy): switch to fixed app branch → Trivy passes → ArgoCD syncs → Kyverno PolicyReport green → pod running
- [ ] **DEMO-03**: Scenario 3 (Live Attack): attack scripts run against deployed app → Falcosidekick UI shows ≥3 matching alerts within 30 seconds → events persisted in `logs/falco.log`

### Documentation & Reproducibility

- [ ] **DOCS-01**: `docs/setup.md` — step-by-step bootstrap guide for fresh macOS install (Rancher Desktop prerequisites included)
- [ ] **DOCS-02**: `docs/scenarios.md` — three demo runbooks with exact commands, expected outputs, and slide cues
- [ ] **DOCS-03**: `docs/architecture.md` — component diagram (three security layers, data flow, network topology)
- [ ] **DOCS-04**: `Makefile` with targets: `up`, `down`, `demo-1`, `demo-2`, `demo-3`, `reset-jenkins`
- [ ] **DOCS-05**: `README.md` with quickstart, prerequisites, and link to thesis context

---

## v2 Requirements

Differentiators — add only after v1 is stable and demo scenarios are rehearsed.

### Supply Chain Integrity

- **SCI-01**: Cosign image signing in Jenkins PUSH stage (`cosign sign`)
- **SCI-02**: Kyverno `verify-image-signatures` policy blocks unsigned images in ArgoCD sync
- **SCI-03**: SBOM diff between vulnerable and fixed build (`cyclonedx-cli diff`)

### Observability

- **OBS-01**: MTTD measurement — timestamp attack script start vs first Falco alert emission; documented in thesis results chapter
- **OBS-02**: MITRE ATT&CK for Containers mapping table in `docs/mitre-mapping.md`
- **OBS-03**: `kube-bench` CIS Kubernetes Benchmark scan as a one-off Job manifest

### Demo Extras

- **DEMO-04**: Scenario D (Policy Denial): push manifest with `privileged: true` → Kyverno denies → PolicyReport shows denial reason
- **DEMO-05**: Bilingual demo runbook (Bulgarian + English)
- **DEMO-06**: Pre-recorded fallback demo (asciinema) for each scenario

---

## Out of Scope

| Feature | Reason |
|---------|--------|
| Cloud deployment (AWS/GCP/Azure) | Thesis is locally runnable only; cloud adds cost and account setup with zero thesis value |
| Multi-node k3s / HA setup | Doubles RAM budget; demonstrates operations, not security |
| OWASP ZAP active scanning | Out of scope per PROJECT.md; attack scripts cover the same demo ground |
| Paid SAST/SCA (Snyk, Mend) | Trivy is free and sufficient; adding paid tools expands scope without novelty |
| SIEM integration (ELK, Splunk) | Weeks of setup; Falcosidekick stdout/file is sufficient for a thesis demo |
| Service mesh (Istio, Linkerd) | 1–2 GB RAM overhead; complicates every other layer |
| Full DVWA / WebGoat | Too many vulnerabilities; dilutes the focused three-layer thesis narrative |
| Blue Ocean Jenkins plugin | Memory-heavy; classic pipeline view is sufficient and lighter |
| Terraform / Ansible | Infra IS the demo — Helm + kubectl + Makefile is the right abstraction |
| Docker Desktop | Conflicts with Rancher Desktop on macOS; use Rancher Desktop only |

---

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 1: Bootstrap | Pending |
| INFRA-02 | Phase 1: Bootstrap | Pending |
| INFRA-03 | Phase 1: Bootstrap | Pending |
| INFRA-04 | Phase 6: Polish | Pending |
| APP-01 | Phase 2: Manual Deploy | Pending |
| APP-02 | Phase 2: Manual Deploy | Pending |
| APP-03 | Phase 2: Manual Deploy | Pending |
| APP-04 | Phase 2: Manual Deploy | Pending |
| APP-05 | Phase 6: Polish | Pending |
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
| DEMO-01 | Phase 6: Polish | Pending |
| DEMO-02 | Phase 6: Polish | Pending |
| DEMO-03 | Phase 6: Polish | Pending |
| DOCS-01 | Phase 6: Polish | Pending |
| DOCS-02 | Phase 6: Polish | Pending |
| DOCS-03 | Phase 6: Polish | Pending |
| DOCS-04 | Phase 6: Polish | Pending |
| DOCS-05 | Phase 6: Polish | Pending |

**Coverage:**
- v1 requirements: 37 total
- Mapped to phases: 37
- Unmapped: 0 ✓

---
*Requirements defined: 2026-07-02*  
*Last updated: 2026-07-02 after research synthesis*
