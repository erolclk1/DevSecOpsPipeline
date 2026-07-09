---
gsd_state_version: 1.0
milestone: v3.4.4
milestone_name: milestone
current_phase: 2
status: unknown
last_updated: "2026-07-09T17:15:54.257Z"
progress:
  total_phases: 6
  completed_phases: 1
  total_plans: 2
  completed_plans: 2
---

# Project State

**Last updated:** 2026-07-02
**Current phase:** 2
**Overall status:** ON TRACK

---

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-07-02)

**Core value:** Demonstrable, locally runnable pipeline where vulnerable container images are automatically blocked, secure images are deployed via GitOps, and cyberattacks are detected in real time — proving DevSecOps concepts work end-to-end.

**Current focus:** Phase 1 — Bootstrap

---

## Phase Status

| Phase | Name | Status | Notes |
|-------|------|--------|-------|
| 1 | Bootstrap | Not started | Registry + k3s + name resolution |
| 2 | Vulnerable App | Not started | Demo app + manual kubectl deploy |
| 3 | GitOps | Not started | ArgoCD + Kyverno |
| 4 | Jenkins CI | Not started | JCasC + Trivy + manifest bump |
| 5 | Runtime Security | Not started | Falco + Falcosidekick + attack scripts |
| 6 | Demo Polish | Not started | Runbooks, Makefile, docs, diagram |

---

## Progress Bar

```
Phase 1 [          ] 0%   Bootstrap
Phase 2 [          ] 0%   Vulnerable App
Phase 3 [          ] 0%   GitOps
Phase 4 [          ] 0%   Jenkins CI
Phase 5 [          ] 0%   Runtime Security
Phase 6 [          ] 0%   Demo Polish
────────────────────────────────────────
Overall  [          ] 0%   0/6 phases complete
```

---

## Completed Work

- [2026-07-02] Feasibility assessment: 7.5/10, feasible with caveats
- [2026-07-02] Diploma assignment filled and protection removed (`Diploma_Zadanie_Final.docx`)
- [2026-07-02] `PROJECT.md` initialized with requirements and key decisions
- [2026-07-02] Research complete: `STACK.md`, `FEATURES.md`, `ARCHITECTURE.md`, `PITFALLS.md`, `SUMMARY.md`
- [2026-07-02] `REQUIREMENTS.md` defined: 37 v1 requirements across 6 phases
- [2026-07-02] `ROADMAP.md` created: 6 phases, full requirement coverage (37/37), success criteria and key risks per phase

---

## Active Decisions

| Decision | Chosen | Rationale |
|----------|--------|-----------|
| Local cluster | Rancher Desktop 1.23.1 | k3d stale (no release since 2024-06); single install; Apple Silicon native |
| Local registry | `registry:2` on host + `registries.yaml` | k3d built-in registry no longer recommended; `host.rancher-desktop.internal:5000` as mirror |
| Jenkins invocation of Trivy | Shell step, not Jenkins plugin | More transparent, easier to debug, identical output, simpler failure modes |
| Jenkins configuration | JCasC from day 1 | Reproducible config; avoids opaque UI wizard state; `casc.yaml` in Git |
| Falco eBPF driver | `driver.kind=modern_ebpf` (explicit, not `auto`) | kmod fails without kernel headers in Rancher Desktop VM; legacy eBPF deprecated in v0.44.0 |
| Repo layout | Mono-repo with ArgoCD sub-path (`deploy/overlays/local/`) | Single `git clone` reproduces entire thesis artefact |
| Admission control | Kyverno with 4 community policies | Added from research; YAML policies more legible than Rego for a thesis committee |
| Demo app language | Node.js 22 LTS (to be confirmed in Phase 2) | Smaller Alpine surface, well-understood SQLi attack path; Python 3.12 also acceptable |
| GitOps rule | Jenkins commits only to Git; never runs `kubectl apply` | Bypassing ArgoCD turns GitOps into decoration; violates thesis thesis thesis central demo scenario |

---

## Blockers

None — ready to start Phase 1.

---

## Open Questions

Sourced from `research/SUMMARY.md`. Each must be answered during the indicated phase.

| # | Question | Resolve in Phase | Why It Matters |
|---|----------|-----------------|----------------|
| 1 | Exact `registries.yaml` syntax for Rancher Desktop 1.23.1 | Phase 1 | Hostname (`host.rancher-desktop.internal` vs `host.lima.internal`) may differ by version; must verify empirically before any Jenkins work |
| 2 | Does RD 1.23.1 expose `host.rancher-desktop.internal` reliably on Apple Silicon? | Phase 1 | If not, may require k3d as fallback despite its 2-year staleness |
| 3 | Exact k3s minor version bundled with RD 1.23.1 | Phase 1 | Run `kubectl version --short` post-install; document in PROJECT.md and `docs/setup.md` |
| 4 | Node.js or Python for demo app? | Phase 2 | Pick one and commit — affects Trivy CVE profile, attack script implementation, and Falco rule conditions |
| 5 | PostgreSQL vs SQLite for demo app? | Phase 2 | PostgreSQL enables a credential-access Falco scenario but adds ~150 MB RAM; SQLite is sufficient for SQL injection demonstration |
| 6 | Current Falco chart: does `driver.kind=auto` auto-select `modern_ebpf` or still try kmod first? | Phase 5 | Even if auto works, pin explicitly for reproducibility; determines whether the default chart is safe to use |
| 7 | Falcosidekick chart values key stability in chart 9.1.0 (e.g. `webui.enabled` vs `webui.create`)? | Phase 5 | Key names occasionally renamed between chart minor versions; verify with `helm show values falcosecurity/falco --version 9.1.0` before writing Helm command |
| 8 | Exact Trivy DB registry URL for `TRIVY_DB_REPOSITORY` fallback in 2026 | Phase 4 | `ghcr.io/aquasecurity/trivy-db` vs `public.ecr.aws/aquasecurity/trivy-db` — verify with `trivy --help` before committing JCasC config |
| 9 | ArgoCD v3.4 default: Server-Side Apply on or off? | Phase 3 | Affects `ignoreDifferences` mitigation for Kyverno-induced sync loops; check ArgoCD v3.4 release notes |

---

## Accumulated Context

### Architecture decisions confirmed by research

- Jenkins MUST NOT run `kubectl apply` — it touches only Git. ArgoCD touches the cluster. This is the central thesis demonstration boundary.
- Component build order is non-negotiable: registry → cluster → demo app → ArgoCD → Jenkins → Falco. Jenkins introduced before a working manual deploy path wastes 4+ hours on environment debugging.
- Trivy must use `--exit-code 1` — never wrapped in `|| true`. Smoke-test with `vulnerables/web-dvwa` to verify the DB is live.
- All Falco custom rules must be scoped with `k8s.ns.name = "demoapp"` — prevents false positives from `argocd`, `kube-system`, `falco` namespaces.
- RAM budget at peak demo load: ~10 GB. Never run Jenkins build + Falco attack simulation concurrently. Serialize all demo scenarios.

### Thesis context

- Institution: ТУ-София (TU-Sofia), катедра "Киберсигурност" (Department of Cybersecurity)
- Programme: МКПКП — Магистър по Киберсигурност и Превенция на Киберпрестъпления
- Supervisor: доц. д-р Я. Томов
- Thesis title: DevSecOps CI/CD Pipeline for Automated Vulnerability Detection and Runtime Security

### Mono-repo layout (planned)

```
myProject/
├── app/            Vulnerable demo app (Node.js/Python REST API)
├── attacks/        Attack simulation scripts (sqli.py, reverse_shell.sh, privilege_probe.sh)
├── ci/             Jenkins JCasC, Jenkinsfile, plugins.txt, docker-compose.yml
├── cluster/        Bootstrap scripts (registries.yaml, one-time setup)
├── deploy/
│   ├── base/       Kustomize base manifests
│   └── overlays/local/   ArgoCD watches this path only
├── docs/           setup.md, scenarios.md, architecture.md
├── falco/          Custom rules + Falcosidekick values
├── logs/           falco.log (Falcosidekick file output, gitignored except .gitkeep)
├── Makefile        up / down / demo-1 / demo-2 / demo-3 / reset-jenkins
└── README.md
```

---

## Todos

- [ ] Start Phase 1: verify Rancher Desktop 1.23.1 install + registry + registries.yaml
- [ ] Resolve Open Question 1: confirm exact hostname inside VM before writing any Jenkinsfile
- [ ] Resolve Open Question 3: document k3s minor version in PROJECT.md after Phase 1
- [ ] Decide Node.js vs Python for demo app (Open Question 4) at Phase 2 start; update PROJECT.md Key Decisions

---

## Session Continuity

To resume this project in a new session:

1. Read `.planning/PROJECT.md` — core value, constraints, key decisions
2. Read `.planning/REQUIREMENTS.md` — 37 v1 requirements with phase assignments
3. Read `.planning/ROADMAP.md` — 6 phases, tasks, success criteria, key risks
4. Read this file (`.planning/STATE.md`) — current position, decisions, open questions
5. Resume at: **Phase 1 — Bootstrap**

The full research context is in `.planning/research/`: `STACK.md`, `FEATURES.md`, `ARCHITECTURE.md`, `PITFALLS.md`, `SUMMARY.md`.

---

## Next Action

Run `/gsd:plan-phase 1` to plan Phase 1: Bootstrap

---

*State initialized: 2026-07-02*
*Last updated: 2026-07-02 after roadmap creation*
