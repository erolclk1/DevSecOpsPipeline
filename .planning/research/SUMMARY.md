# Research Summary — DevSecOps Pipeline Thesis

**Synthesized:** 2026-07-02  
**Sources:** STACK.md · FEATURES.md · ARCHITECTURE.md · PITFALLS.md  
**Feeds into:** REQUIREMENTS.md · ROADMAP.md

---

## Executive Summary

- **k3d is stale (no release since June 2024) — use Rancher Desktop 1.23.1 + `registry:2`.** The k3d registry auto-wiring advantage is outweighed by 2-year staleness; configure Rancher Desktop with `registries.yaml` instead.
- **Jenkins requires Java 21 (mandatory since LTS 2.555.1).** Use `jenkins/jenkins:2.555.3-lts-jdk21`. Any older image or tutorial that skips this will fail.
- **Registry name-parity is the #1 local blocker.** `localhost:5000` on the host ≠ `localhost:5000` inside the Rancher Desktop VM. Solve this in Phase 1 before writing a single Jenkinsfile.
- **Kyverno (4 policies) is added to the scope.** It fills the GitOps admission-control layer that was implicitly required but unnamed in the original requirements. YAML policies are more legible than Rego for a thesis committee.
- **Falco legacy eBPF is deprecated in v0.44.0; `modern_ebpf` is the only viable driver.** This was already a project decision — confirmed and locked in.
- **Component build order is non-negotiable:** registry → cluster → ArgoCD → demo app → Jenkins → Falco. Jenkins is the highest-risk component; it must not be introduced before a working manual deploy path exists to observe.
- **The demo app's vulnerability design is as important as the pipeline.** Intentional, minimal, deterministic vulnerabilities (SQL injection + command injection) beat DVWA/WebGoat for a focused thesis defence.

---

## Confirmed Stack (Pinned Versions)

| Component | Version | Notes |
|-----------|---------|-------|
| Jenkins LTS | **2.555.3** | Image: `jenkins/jenkins:2.555.3-lts-jdk21`. Java 21 mandatory. |
| ArgoCD | **v3.4.4** | Helm chart `argo/argo-cd 10.1.0`. Avoid v3.5 RC. |
| Trivy | **v0.72.0** | CLI shell step, NOT Jenkins plugin. `--ignore-unfixed` flag essential. |
| Falco | **0.44.1** | Helm chart `falcosecurity/falco 9.1.0`. `driver.kind=modern_ebpf` explicit. |
| Falcosidekick | bundled in chart | File output + webui. ~250 MB added RAM. |
| Kyverno | latest stable | 4 community policies. YAML, not Rego. |
| Rancher Desktop | **1.23.1** | Docker + k3s on macOS. Single install. |
| k3s (bundled) | v1.32.x | Via Rancher Desktop. Verify exact minor with `kubectl version` post-install. |
| Docker registry | `registry:2.8.3+` | Host container, port 5000. Configured via Rancher Desktop `registries.yaml`. |
| Demo app runtime | **Node.js 22 LTS** | `node:22-alpine` for clean Trivy scan surface. Python 3.12 also acceptable. |
| k3d | ~~v5.9.0~~ **REJECTED** | No release since 2024-06-02. Do not default to it. |

---

## Architecture Pattern

### Mono-repo with ArgoCD sub-path (single-developer, thesis scale)

```
myProject/
├── app/            Vulnerable demo app (Node.js/Python REST API)
├── ci/             Jenkins JCasC, Dockerfile, Jenkinsfile, scripts
├── deploy/
│   ├── base/       Kustomize base manifests
│   └── overlays/local/   ← ArgoCD watches THIS path only
├── falco/          Custom rules + Falcosidekick values
├── cluster/        Bootstrap scripts (one-time)
├── attacks/        Attack simulation scripts (sqli.py, reverse_shell.sh)
└── Makefile        up / down / demo-{1,2,3} targets
```

ArgoCD points at `deploy/overlays/local/`. Jenkins commits only to that subdirectory (one-line Kustomize image-tag bump). Result: one `git clone` reproduces the entire thesis artefact.

### Registry topology

```
Jenkins (host) ──docker push──► host.rancher-desktop.internal:5000
kubelet (VM)   ──image pull──►  host.rancher-desktop.internal:5000  (via registries.yaml)
```

Configure `~/.rd/k3s/registries.yaml` in Rancher Desktop. Reference the registry by hostname everywhere — never by IP (breaks on DHCP roam / VM restart).

### Critical anti-pattern

**Jenkins MUST NOT `kubectl apply` directly.** Jenkins touches only Git. ArgoCD touches the cluster. Bypassing this turns ArgoCD into decoration and breaks the entire GitOps demonstration layer.

### Component build order

| # | Step | Verification |
|---|------|-------------|
| 1 | `registry:2` container + `registries.yaml` | `curl http://host.rancher-desktop.internal:5000/v2/` → `{}` |
| 2 | k3s cluster (Rancher Desktop) | `kubectl get nodes` → Ready |
| 3 | Demo app skeleton + Dockerfile | `docker build && docker run` → 200 on `GET /` |
| 4 | Push to registry, **raw `kubectl apply`** | Pod pulls image, Service reachable from host |
| 5 | ArgoCD via Helm | ArgoCD UI reachable via port-forward |
| 6 | ArgoCD Application → `deploy/overlays/local/` | Manual git edit → auto-sync visible |
| 7 | Jenkins (JCasC + Trivy baked in) | Jenkins boots with pipeline job pre-configured |
| 8 | Full Jenkinsfile: build → scan → push → bump | Green pipeline → new pod version running |
| 9 | Vulnerable base image introduced | Scenario 1: pipeline blocks, no push |
| 10 | Falco + Falcosidekick | Startup logs clean; no errors |
| 11 | Custom Falco rules | Syntax validated on load |
| 12 | Attack scripts + alert log | Scenario 3: attack fires named rule to file |

---

## Feature Scope

### Table Stakes (must ship)

- Vulnerable demo app: SQL injection + command injection endpoints, deliberately outdated base image (`node:14` or `python:3.9` vintage), runs as root initially
- Dockerfile with pinned old digest (guarantees Trivy CVEs on every demo)
- Jenkins declarative pipeline: BUILD → SCAN (Trivy, `--exit-code 1`) → PUSH → BUMP MANIFEST
- SBOM output per build (`trivy image --format cyclonedx`) archived as artefact
- ArgoCD Application with auto-sync + self-heal watching `deploy/overlays/local/`
- Kyverno 4 policies: `disallow-latest-tag`, `restrict-image-registries`, `disallow-privileged-containers`, `require-resource-limits`
- Falco DaemonSet (`modern_ebpf`) + 5 custom rules (see below)
- Falcosidekick file output + webui
- 3 attack simulation scripts: SQL injection, reverse shell (via command injection), privilege probe
- 3 demo scenarios: blocked build, successful deploy, live attack detected
- One-command bootstrap (`make up`) + demo runbook + teardown script

### 5 Custom Falco Rules

| Rule | Detects |
|------|---------|
| Reverse shell in container | `nc -e`, `bash -i`, `/dev/tcp` redirection |
| Shell spawned by web server | `bash`/`sh` child of `node`/`python` process |
| Read sensitive file | `/etc/shadow`, `/etc/sudoers`, `.ssh/*` |
| Package management in container | `apk`, `apt`, `pip install` at runtime |
| Contact K8s API from app pod | App pod hitting `kubernetes.default.svc` |

All rules scoped by `k8s.ns.name = "demoapp"` to prevent false positives from `kube-system`/`argocd`.

### Differentiators (add if time permits)

- Falcosidekick → webhook to local receiver (live-updating web page during demo)
- MITRE ATT&CK for Containers mapping table (T1059 → rule → screenshot)
- Kyverno `verify-image-signatures` + Cosign signing in Jenkins
- MTTD measurement (timestamp attack start vs first Falco alert)
- Bilingual demo runbook (BG + EN)

### Anti-Features (explicitly out)

Cloud deployment, OWASP ZAP, multi-cluster, SIEM/ELK, Terraform/Ansible, service mesh, paid tools, full DVWA/WebGoat, eBPF custom probes.

---

## Top 7 Pitfalls & Mitigations

| # | Pitfall | Mitigation |
|---|---------|-----------|
| 1 | `localhost:5000` unreachable from k3s VM | Use `host.rancher-desktop.internal:5000` + `registries.yaml`. Verify with `kubectl run curl` before any Jenkins work. |
| 2 | Jenkins Docker socket on controller (not agent) | Mount socket only on a dedicated agent container; controller keeps clean `jenkins_home` only. |
| 3 | Falco `CrashLoopBackOff` — kmod fails | `--set driver.kind=modern_ebpf` explicit; do not rely on `auto`. Verify `uname -r ≥ 5.8` and `/sys/kernel/btf/vmlinux` exists. |
| 4 | RAM blowout on 16 GB machine | Set explicit `resources.limits` on all Helm releases. Rancher Desktop VM: 6 GB. Serialize builds and attack demos — never concurrent. |
| 5 | Jenkins first green run takes 4–6 hours | JCasC from day 1; pin plugin versions in `plugins.txt`; iterate Jenkinsfile with `Replay`; keep `jenkins-reset.sh` for clean reprovisioning. |
| 6 | Trivy exit code not enforced (`--exit-code 1` missing) | Never wrap Trivy in `|| true`. Smoke-test with `vulnerables/web-dvwa` — if it reports clean, the DB is broken. |
| 7 | Falco custom rules too noisy / false positives | Scope by `k8s.ns.name`; combine `proc.name` + `fd.sip` + `container.image.repository`; add exceptions for `kubectl exec` debugging sessions. |

---

## Recommended Phase Order

| Phase | Name | Goal | Key Risk |
|-------|------|------|---------|
| 1 | Bootstrap | Registry + cluster + name resolution working end-to-end | Registry cross-network (Pitfall 1) |
| 2 | Manual Deploy | Demo app built, pushed, deployed via raw `kubectl apply` | Intentional vulnerability design (Pitfall 11) |
| 3 | GitOps | ArgoCD + Kyverno; manual git edit triggers sync | Sync loops / ImagePullBackOff (Pitfalls 7, 8) |
| 4 | Jenkins CI | JCasC + Trivy scan + manifest bump automates Phase 2-3 | First green run time (Pitfall 5) |
| 5 | Runtime Security | Falco + custom rules + Falcosidekick + attack scripts | False positives, modern_ebpf (Pitfalls 3, 6) |
| 6 | Demo Polish | 3 scenario runbooks, Makefile, docs, architecture diagram | RAM under load; pre-recorded fallback (Pitfall 4) |

Rationale: each phase is testable in isolation. ArgoCD must exist before Jenkins so there is an observable GitOps path the moment Jenkins first pushes. Falco is last because it observes running workloads — it needs Phase 2-4 to be stable first.

---

## Open Questions (Must Answer During Implementation)

| Question | Resolve When | Why It Matters |
|----------|-------------|---------------|
| Exact `registries.yaml` syntax for Rancher Desktop 1.23.1 | Phase 1 | Hostname (`host.rancher-desktop.internal` vs `host.lima.internal`) may differ by version |
| Does RD 1.23.1 expose `host.rancher-desktop.internal` reliably on Apple Silicon? | Phase 1 | If not, may force k3d as fallback despite staleness |
| Exact k3s minor version bundled with RD 1.23.1 | Phase 1 | `kubectl version --short` post-install |
| Node.js or Python for demo app? | Phase 2 | Pick one and commit — affects Trivy CVE profile and attack scripts |
| PostgreSQL vs SQLite for demo app? | Phase 2 | PostgreSQL enables credential-access Falco scenario; +150 MB RAM |
| Current Falco chart: does `driver.kind=auto` auto-select `modern_ebpf` or does it still try kmod first? | Phase 5 | If auto works, still pin explicitly for reproducibility |
| Falcosidekick chart values key stability in chart 9.1.0 (e.g. `webui.enabled` vs `webui.create`) | Phase 5 | Occasionally renamed between chart minor versions |
| Exact Trivy DB registry URL for `TRIVY_DB_REPOSITORY` fallback in 2026 | Phase 4 | `ghcr.io/aquasecurity/trivy-db` vs `public.ecr.aws/aquasecurity/trivy-db` — verify with `trivy --help` |
| ArgoCD v3.4 default: Server-Side Apply on or off? | Phase 3 | Affects `ignoreDifferences` mitigation for sync loops |

---

## Confidence & Gaps

| Area | Confidence | Notes |
|------|------------|-------|
| Pinned versions (all tools) | HIGH | Verified against official GitHub releases 2026-07-02 |
| Registry topology (Rancher Desktop) | MEDIUM | Exact hostname needs empirical Phase 1 verification |
| Falco custom rule syntax | MEDIUM | Rule names verified against upstream; exact YAML should be cross-checked against chart 9.1.0 |
| Kyverno policy YAML | MEDIUM | Names from community catalogue; version-pin before implementing |
| ArgoCD v3.x sync behaviour | MEDIUM | General patterns are stable; specific 2026 defaults unverified |
| RAM estimates | MEDIUM | Order-of-magnitude; actuals vary with Rancher Desktop version and app size |
| k3d as fallback | LOW-MEDIUM | 2-year staleness flagged; document but do not default to it |

No fundamental conflicts between research files. ARCHITECTURE.md originally leaned toward k3d for registry; STACK.md's staleness finding overrides this in favour of Rancher Desktop + `registries.yaml`. All other recommendations are mutually consistent.
