---
gsd_state_version: 1.0
milestone: v3.4.4
milestone_name: milestone
current_phase: 06
status: unknown
last_updated: "2026-08-31T07:53:08.832Z"
progress:
  total_phases: 6
  completed_phases: 4
  total_plans: 18
  completed_plans: 13
---

# Project State

**Last updated:** 2026-08-31
**Current phase:** 06
**Overall status:** ON TRACK

---

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-07-02)

**Core value:** Demonstrable, locally runnable pipeline where vulnerable container images are automatically blocked, secure images are deployed via GitOps, and cyberattacks are detected in real time — proving DevSecOps concepts work end-to-end.

**Current focus:** Phase 06 — Demo Polish

---

## Phase Status

| Phase | Name | Status | Notes |
|-------|------|--------|-------|
| 1 | Bootstrap | Complete | Registry + k3s + name resolution (2026-07-09) |
| 2 | Vulnerable App | Complete | demoapp:6af2848 deployed, 4/4 SC passed (2026-07-23) |
| 3 | GitOps | Complete | ArgoCD v3.4.4 + Kyverno v1.18.2, 10/10 SC passed (2026-08-12) |
| 4 | Jenkins CI | Complete | JCasC + Trivy gate + GitOps bump, both scenarios green (2026-08-21) |
| 5 | Runtime Security | Not started | Falco + Falcosidekick + attack scripts |
| 6 | Demo Polish | Not started | Runbooks, Makefile, docs, diagram |

---

## Progress Bar

```
Phase 1 [██████████] 100% Bootstrap
Phase 2 [██████████] 100% Vulnerable App
Phase 3 [██████████] 100% GitOps
Phase 4 [██████████] 100% Jenkins CI
Phase 5 [          ]   0% Runtime Security
Phase 6 [          ]   0% Demo Polish
────────────────────────────────────────
Overall  [██████▌   ]  67% 4/6 phases complete
```

---

## Completed Work

- [2026-07-02] Feasibility assessment: 7.5/10, feasible with caveats
- [2026-07-02] Diploma assignment filled and protection removed (`Diploma_Zadanie_Final.docx`)
- [2026-07-02] `PROJECT.md` initialized with requirements and key decisions
- [2026-07-02] Research complete: `STACK.md`, `FEATURES.md`, `ARCHITECTURE.md`, `PITFALLS.md`, `SUMMARY.md`
- [2026-07-02] `REQUIREMENTS.md` defined: 37 v1 requirements across 6 phases
- [2026-07-02] `ROADMAP.md` created: 6 phases, full requirement coverage (37/37), success criteria and key risks per phase
- [2026-07-09] Phase 1 complete: registry:2 on port 5001, registries.yaml, k3s verified
- [2026-07-23] Phase 2 complete: demoapp:6af2848 deployed, Trivy CRITICAL CVEs confirmed, SQLi + CMDi exploitable, 4/4 SC passed
- [2026-08-12] Phase 3 complete: ArgoCD v3.4.4 Synced/Healthy, Kyverno v1.18.2 with 4 ClusterPolicies, :latest blocked, no sync loop, 10/10 SC passed
- [2026-08-14] Phase 4 Plan 04-test-scaffolds complete: Wave 0 CI validation harness (Dockerfile.fixed + smoke-test.sh + verify-jcasc.sh + scenario-1/2.sh); CI-03/04/05 requirements marked; scripts run later on Windows target
- [2026-08-21] Phase 4 complete: Jenkins 2.555.3-lts-jdk21 via JCasC, docker-builder agent with Trivy v0.72.0 + yq v4, 4-stage Jenkinsfile (BUILD/SCAN/PUSH/BUMP), Scenario 1 (vulnerable image blocked at SCAN) and Scenario 2 (fixed image deployed via ArgoCD) both verified on Windows/Rancher Desktop target. 7/7 CI requirements met.
- [2026-08-31] Phase 6 Plan 01 complete: Makefile upgraded — up: STOP message, stack: target (phases 3-5 chain), demo-warmup: target (k3s + ArgoCD + Trivy DB pre-warm); INFRA-04 + DOCS-04 requirements addressed
- [2026-08-31] Phase 6 Plan 03 complete: docs/architecture.md (Mermaid component diagram with three security layers, data flow, network topology, key decisions table) + docs/DEMO-SCRIPT.md (line-by-line thesis committee script with Bulgarian narration, pre-demo checklist, fallback procedures, Q&A prep). DOCS-03 requirement met.

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

None — Phase 4 complete. Ready to start Phase 5.

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
| 8 | ~~Exact Trivy DB registry URL for `TRIVY_DB_REPOSITORY` fallback in 2026~~ | **RESOLVED (Phase 4)** | Default primary is `mirror.gcr.io/aquasec/trivy-db`; ECR fallback `public.ecr.aws/aquasecurity/trivy-db` valid. |
| 9 | ArgoCD v3.4 default: Server-Side Apply on or off? | Phase 3 | Affects `ignoreDifferences` mitigation for Kyverno-induced sync loops; check ArgoCD v3.4 release notes |

---

## Accumulated Context

### Phase 4 empirical findings (confirmed on Windows/WSL2 target, 2026-08-21)

- **Docker socket is `/var/run/docker.sock`** on Windows/WSL2 with Rancher Desktop dockerd engine — NOT `~/.rd/docker.sock` (that is macOS/lima only). Compose mount for the agent is `/var/run/docker.sock:/var/run/docker.sock`.
- **Dynamic GID fixup required in entrypoint**: the socket's GID at container runtime differs from what was baked into the agent image. `ci/agent-entrypoint.sh` detects the actual GID at startup via `stat -c '%g' /var/run/docker.sock` and creates/re-creates the `docker` group with that GID before exec-ing the agent.
- **Docker static binary** (`docker-28.3.3.tgz` from download.docker.com) used in the agent image instead of the `docker.io` Debian package — the apt package caused issues on this setup.
- **Jenkins CSRF crumb required for `buildWithParameters`**: simple `curl -X POST` gets HTTP 403. Scripts must first `GET /crumbIssuer/api/json` with a cookie jar, extract `crumbRequestField` + `crumb`, then POST with the header + cookie.
- **Queue item tracking** in scenario-2.sh: trigger returns a `Location:` header with the queue item URL; poll that URL until `"number"` appears, then track that specific build number — avoids `lastBuild` race conditions.
- **`package.fixed.json` / `package-lock.fixed.json`**: the fixed Dockerfile uses separate package files renamed on COPY (`COPY package.fixed.json ./package.json`) so `npm ci` runs cleanly. express@4.22.2 + mysql@2.18.1 have no HIGH/CRITICAL npm CVEs.
- **OS-layer CVEs in `node:22-alpine`**: 8 Alpine package CVEs (busybox, musl, libssl etc.) with no upstream fix land in `.trivyignore`. These are NOT npm issues — the npm tree is clean. The `.trivyignore` + `--ignorefile` pattern is the standard DevSecOps "accepted risk" documentation approach.
- **`[skip ci]` confirmed working**: BUMP commits do not re-trigger the pipeline. Git log shows Jenkins BUMP commits (`ci: bump demoapp to <sha> [skip ci]`) followed by silence — no infinite loop.

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

- [ ] Start Phase 5: install Falco 0.44.1 via `helm upgrade --install` with `driver.kind=modern_ebpf`
- [ ] Resolve Open Question 6: confirm `driver.kind=auto` behavior on Rancher Desktop before first Falco install
- [ ] Resolve Open Question 7: verify Falcosidekick chart key names in chart 9.1.0 before writing Helm command

---

## Session Continuity

To resume this project in a new session:

1. Read `.planning/PROJECT.md` — core value, constraints, key decisions
2. Read `.planning/REQUIREMENTS.md` — 37 v1 requirements with phase assignments
3. Read `.planning/ROADMAP.md` — 6 phases, tasks, success criteria, key risks
4. Read this file (`.planning/STATE.md`) — current position, decisions, open questions
5. Resume at: **Phase 5 — Runtime Security**

The full research context is in `.planning/research/`: `STACK.md`, `FEATURES.md`, `ARCHITECTURE.md`, `PITFALLS.md`, `SUMMARY.md`.

---

## Next Action

Run `/gsd:plan-phase 5` to plan Phase 5: Runtime Security (Falco + Falcosidekick + attack scripts)

---

*State initialized: 2026-07-02*
*Last updated: 2026-07-02 after roadmap creation*
