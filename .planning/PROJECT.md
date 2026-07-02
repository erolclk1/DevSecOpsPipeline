# DevSecOps Pipeline — Cybersecurity Thesis Project

## What This Is

End-to-end DevSecOps system demonstrating a secure CI/CD pipeline with automated vulnerability scanning, GitOps-based deployment with security policies, and runtime attack detection. Built as a locally runnable thesis project for a Master's degree in Cybersecurity and Cybercrime Prevention at TU-Sofia, covering three security control layers: shift-left (Trivy), GitOps policy enforcement (ArgoCD), and runtime detection (Falco).

## Core Value

A demonstrable, locally runnable pipeline where vulnerable container images are automatically blocked, secure images are deployed via GitOps, and cyberattacks are detected in real time — proving DevSecOps concepts work end-to-end.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Vulnerable demo application (Node.js/Python REST API with SQL injection)
- [ ] Dockerfile and container build for the demo app
- [ ] Jenkins CI pipeline (build → Trivy scan → block/push → update manifest)
- [ ] Local Docker registry accessible from host and k3s cluster
- [ ] Kubernetes manifests (Deployment, Service, Namespace, ConfigMap)
- [ ] ArgoCD GitOps deployment syncing from Git manifest repo
- [ ] Falco runtime security with custom rules (reverse shell, suspicious process)
- [ ] Attack simulation scripts (SQL injection, port scan, reverse shell)
- [ ] Three demonstration scenarios (blocked build, successful deploy, attack detected)
- [ ] Step-by-step setup guide for the full local environment

### Out of Scope

- Cloud deployment (AWS/GCP/Azure) — thesis is locally runnable only
- Production-grade HA setup — single-node k3s is sufficient
- Mend/Snyk paid scanning — Trivy is free and sufficient
- OWASP ZAP active scanning — curl/Python scripts cover the demo scenarios
- Multi-cluster setup — one local cluster demonstrates the concepts
- Paid CI services (GitHub Actions cloud) — Jenkins runs locally

## Context

- **Platform:** macOS (Apple Silicon compatible) + Linux
- **Cluster:** k3s via Rancher Desktop — lightest option, avoids Minikube hypervisor overhead
- **Registry:** Local Docker registry, must be reachable from both host (Jenkins) and k3s VM
- **Falco:** Must use `driver.kind: modern_ebpf` on Rancher Desktop — kmod path fails without kernel headers
- **Jenkins:** Biggest setup risk — Docker socket binding + JCasC config + Trivy shell step (not plugin)
- **RAM budget:** ~8-10 GB steady state on 16 GB machine; no concurrent Jenkins builds + attack simulations
- **Thesis context:** МКПКП (Магистър по Киберсигурност и Превенция на Киберпрестъпления), ТУ-София, катедра "Киберсигурност", доц. д-р Я. Томов

## Constraints

- **Tech stack**: Jenkins, ArgoCD, Docker, k3s, Trivy, Falco, Node.js or Python — fixed by thesis assignment
- **Environment**: Must run locally on a single developer laptop (16 GB RAM)
- **Git**: Local git repo for now; remote GitHub repo to be added by student
- **Language**: Demo app in Node.js or Python (simplest REST API)
- **Security**: Attack scripts run only against owned/local containers — never external targets

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| k3s via Rancher Desktop over Minikube | 512MB baseline vs 2-4GB; no hypervisor quirks on macOS | — Pending |
| Trivy as shell step, not Jenkins plugin | More transparent, easier to debug, same output | — Pending |
| JCasC for Jenkins from day 1 | Reproducible config, avoids opaque UI wizard state | — Pending |
| modern_ebpf for Falco | kmod requires kernel headers not available in Rancher Desktop VM | — Pending |
| k3d for local registry | Avoids manual IP alignment between host and k3s VM | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-07-02 after initialization*
