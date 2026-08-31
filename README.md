# DevSecOps CI/CD Pipeline — Cybersecurity Thesis

A locally runnable DevSecOps pipeline demonstrating three complementary security control layers:

- **Shift-left** — Trivy scans container images in Jenkins and blocks builds with HIGH/CRITICAL CVEs
- **GitOps policy** — ArgoCD syncs from Git; Kyverno admission control enforces four policies at deploy time
- **Runtime detection** — Falco (modern_ebpf) detects syscall-level attacks in real time via Falcosidekick

All three scenarios run on a single Windows/WSL2 machine with Rancher Desktop. No cloud account required.

> **WARNING:** This repository contains intentionally vulnerable software for thesis demonstration
> purposes only. It MUST NOT be deployed outside a **local, isolated environment**. Do NOT expose
> any component on a network interface accessible from the internet.

---

## Architecture

```
Developer --> Git Repo --> Jenkins CI --> [SCAN fails] --> Build Blocked (no push)
                               |
                               +-- [SCAN passes] --> Registry (localhost:5001)
                                                          |
                                                 ArgoCD auto-sync
                                                          |
                                               Kyverno admission
                                                          |
                                               k3s Cluster (demoapp ns)
                                                          |
                                               Falco (modern_ebpf)
                                                          |
                                               Falcosidekick
                                               (webui + file sink)
                                                          ^
                                               Attack Scripts ----------+
```

---

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| Windows 10/11 + WSL2 | -- | Target/pipeline machine |
| Rancher Desktop | 1.23.1 | [Download](https://github.com/rancher-sandbox/rancher-desktop/releases/tag/v1.23.1) |
| RAM | 16 GB (12 GB min) | Set VM to 6 GB in RD Preferences |
| Git | any | -- |
| Python 3 | 3.10+ | For SQL injection demo script |

> **macOS (dev machine only):** Code authoring only. All Make targets must run on the Windows/WSL2 target.

---

## Quickstart

```bash
# 1. Clone the repo
git clone <repo-url>
cd myProject

# 2. Bootstrap Phase 1 (registry + registry config)
make up
#    ^ This prints a STOP message. Restart Rancher Desktop before step 3.
#    Run: rdctl shutdown && rdctl start
#    Wait for Kubernetes: Running in the tray icon.

# 3. Install all stack components (ArgoCD + Kyverno + Jenkins + Falco)
make stack

# 4. Pre-warm Trivy DB (run BEFORE the committee arrives)
make demo-warmup

# 5. Run demos
make demo-1   # Blocked build -- Trivy shift-left
make demo-2   # Successful deploy -- GitOps pipeline
make demo-3   # Live attack -- Falco runtime detection
```

---

## Demo Scenarios

| Scenario | Command | What It Proves |
|----------|---------|----------------|
| 1 -- Blocked Build | `make demo-1` | Trivy detects HIGH/CRITICAL CVEs; Jenkins SCAN stage fails; image is NOT pushed to registry |
| 2 -- Successful Deploy | `make demo-2` | Fixed image passes Trivy; ArgoCD auto-syncs to cluster; Kyverno admits the SHA-tagged pod |
| 3 -- Live Attack | `make demo-3` | SQL injection + reverse shell + privilege probe trigger named Falco alerts within 30 s |

See [`docs/scenarios.md`](docs/scenarios.md) for full runbooks with exact commands, expected output, and timing.

---

## Stack Versions (Pinned)

| Component | Version |
|-----------|---------|
| Rancher Desktop | 1.23.1 |
| Jenkins LTS | 2.555.3-lts-jdk21 |
| ArgoCD | v3.4.4 (Helm chart 10.1.0) |
| Trivy | v0.72.0 |
| Falco | 0.44.1 (Helm chart 9.1.0) |
| Kyverno | latest stable |
| Docker registry | `registry:2` on port 5001 |
| Demo app | Node.js 22 LTS (`node:22-alpine` prod / old digest vuln demo) |

---

## Documentation

| Doc | Purpose |
|-----|---------|
| [`docs/setup.md`](docs/setup.md) | Full bootstrap guide for a fresh machine |
| [`docs/scenarios.md`](docs/scenarios.md) | Demo runbooks with expected output |
| [`docs/architecture.md`](docs/architecture.md) | Component diagram, data flow, network topology |
| [`docs/DEMO-SCRIPT.md`](docs/DEMO-SCRIPT.md) | Line-by-line committee presentation script |
| [`app/README.md`](app/README.md) | Vulnerability documentation (OWASP 2021) |

---

## Repo Layout

```
myProject/
+-- app/            Vulnerable demo REST API (Node.js 22)
+-- attacks/        Attack simulation scripts (sqli, reverse shell, privilege probe)
+-- ci/             Jenkins JCasC + Jenkinsfile + docker-compose.yml
+-- cluster/        Bootstrap scripts (registries.yaml, insecure-registry provisioning)
+-- deploy/
|   +-- base/       Kustomize base manifests
|   +-- overlays/local/   <- ArgoCD watches this path only
+-- docs/           Setup guide, scenario runbooks, architecture diagram
+-- falco/          Custom Falco rules + Falcosidekick Helm values
+-- logs/           falco.log (Falcosidekick file output; .gitignore except .gitkeep)
+-- bootstrap/      ArgoCD + Kyverno install scripts
+-- Makefile        up / stack / down / demo-1/2/3 / demo-warmup / reset-jenkins
```

---

## Thesis Context

- **Institution:** TU-Sofia (ТУ-София), катедра "Киберсигурност"
- **Programme:** МКПКП -- Магистър по Киберсигурност и Превенция на Киберпрестъпления
- **Supervisor:** доц. д-р Я. Томов
- **Title:** DevSecOps CI/CD Pipeline for Automated Vulnerability Detection and Runtime Security
