# DevSecOps Pipeline — Cybersecurity Thesis

Locally-runnable DevSecOps CI/CD pipeline demonstrating three security control layers:
shift-left (Trivy), GitOps policy enforcement (ArgoCD + Kyverno), and runtime detection (Falco).
Master's thesis project, TU-Sofia, катедра "Киберсигурност".

## Project State

See `.planning/STATE.md` for current phase status and open questions.
See `.planning/ROADMAP.md` for 6-phase plan with tasks and success criteria.
See `.planning/REQUIREMENTS.md` for all 37 v1 requirement IDs.

**Current phase:** Ready to start Phase 1 — Bootstrap

## Stack (Pinned Versions)

| Component | Version | Notes |
|-----------|---------|-------|
| Rancher Desktop | 1.23.1 | Docker + k3s on **Windows (WSL2)**. Target/pipeline machine. NOT Docker Desktop. Dev machine is macOS (code only). |
| Jenkins LTS | 2.555.3 | Image: `jenkins/jenkins:2.555.3-lts-jdk21`. Java 21 required. |
| ArgoCD | v3.4.4 | Helm chart `argo/argo-cd 10.1.0` |
| Trivy | v0.72.0 | CLI shell step only — NOT Jenkins plugin |
| Falco | 0.44.1 | Helm chart `falcosecurity/falco 9.1.0` |
| Kyverno | latest stable | 4 community policies |
| Docker registry | `registry:2` | Host container, port 5001 (5000 conflicts with Rancher Desktop's internal proxy) |
| Demo app | Node.js 22 LTS | `node:22-alpine` base (prod), old pinned digest (vuln demo) |

## Architecture

```
Git repo (mono-repo)
├── app/          Vulnerable demo REST API
├── ci/           Jenkins JCasC + Jenkinsfile + Dockerfile
├── deploy/
│   ├── base/     Kustomize base manifests
│   └── overlays/local/   ← ArgoCD watches THIS path only
├── falco/        Custom rules + Falcosidekick values
├── attacks/      Attack simulation scripts (localhost targets only)
└── Makefile      up / down / demo-{1,2,3} targets
```

Jenkins → Git only (never `kubectl apply`). ArgoCD → cluster only. This separation IS the GitOps thesis demonstration.

## Critical Rules

1. **Jenkins MUST NOT `kubectl apply` directly.** Jenkins commits to `deploy/overlays/local/` only. ArgoCD syncs to cluster.
2. **Falco must use `driver.kind=modern_ebpf`** — Rancher Desktop VM has no kernel headers; kmod fails.
3. **Registry hostname is `host.rancher-desktop.internal:5001`** — never `localhost:5001` in manifests (breaks inside VM). Never hardcode an IP (breaks on DHCP roam). Port 5001 is used because Rancher Desktop binds port 5000 internally.
4. **Image tags are always git short SHA** — never `:latest`. Enforced by Kyverno `disallow-latest-tag` policy.
5. **Attack scripts target localhost/cluster only** — ethical constraint; scripts must refuse to run against external targets.

## Key Files

- `.planning/PROJECT.md` — project context, decisions, constraints
- `.planning/REQUIREMENTS.md` — 37 v1 requirements with REQ-IDs
- `.planning/ROADMAP.md` — 6-phase plan with tasks and success criteria per phase
- `.planning/STATE.md` — current status, open questions, completed work
- `.planning/research/SUMMARY.md` — synthesized research findings

## GSD Workflow

This project uses the `/gsd` workflow system.

- **Start a phase:** `/gsd:plan-phase <N>`
- **Execute a planned phase:** `/gsd:execute-phase <N>`
- **Check progress:** `/gsd:progress`
- **Transition between phases:** `/gsd:transition`

**Next action:** `/gsd:plan-phase 1`
