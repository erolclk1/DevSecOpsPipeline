# Phase 6: Demo Polish — Research

**Researched:** 2026-08-31
**Domain:** Makefile orchestration, technical documentation, thesis demo scripting
**Confidence:** HIGH (all findings from direct file inspection of the repo; no external dependencies)

---

## Project Constraints (from CLAUDE.md)

- Target/pipeline machine is **Windows with WSL2 + Rancher Desktop 1.23.1** — dev machine is macOS (code only).
- Registry hostname: `host.rancher-desktop.internal:5001` in all k8s manifests. Push from host via `localhost:5001`.
- **Registry port is 5001**, not 5000. Rancher Desktop binds port 5000 internally.
- `dockerd` engine ignores `registries.yaml` — `insecure-registries` in `/etc/docker/daemon.json` inside VM is the actual fix. Applied via `cluster/insecure-registry.start` provisioning script.
- Jenkins MUST NOT `kubectl apply` — commits only to `deploy/overlays/local/`. ArgoCD syncs to cluster.
- Falco driver: `driver.kind=modern_ebpf` (explicit). kmod fails on Rancher Desktop.
- Image tags always git short SHA — never `:latest`. Enforced by Kyverno `disallow-latest-tag`.
- Peak RAM budget: 10 GB. **Never run Jenkins build + Falco attack simultaneously.** All demo scenarios are sequential.
- Attack scripts must target localhost/cluster only. No external targets.

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INFRA-04 | One-command bootstrap script (`make up`) installs all cluster components from scratch | Makefile audit shows `up` currently only runs `phase-1` + prints manual instructions. Needs to chain all phases automatically. |
| APP-05 | App has a README documenting each vulnerability with OWASP 2021 category reference | `app/README.md` does NOT exist. `server.js` has inline `// INTENTIONALLY VULNERABLE` comments that can be referenced directly. |
| DEMO-01 | Scenario 1 (Blocked Build): pipeline run with vulnerable image → Trivy fails → image NOT pushed → Jenkins shows red stage | `demo-1` Makefile target exists; calls `ci/tests/scenario-1.sh`. Content + verification need documenting. |
| DEMO-02 | Scenario 2 (Successful Deploy): switch to fixed app branch → Trivy passes → ArgoCD syncs → Kyverno PolicyReport green → pod running | `demo-2` Makefile target exists; calls `ci/tests/scenario-2.sh`. |
| DEMO-03 | Scenario 3 (Live Attack): attack scripts run → Falcosidekick UI shows ≥3 alerts within 30 s → events persisted in `logs/falco.log` | `demo-3` Makefile target exists; calls all three attack scripts + copies log. |
| DOCS-01 | `docs/setup.md` — step-by-step bootstrap guide (Rancher Desktop prerequisites included) | `docs/` directory does NOT exist. Must be created from scratch. |
| DOCS-02 | `docs/scenarios.md` — three demo runbooks with exact commands, expected outputs, and slide cues | Does not exist. |
| DOCS-03 | `docs/architecture.md` — component diagram (three security layers, data flow, network topology) | Does not exist. CLAUDE.md has ASCII diagram that can be adapted. |
| DOCS-04 | Makefile with targets: `up`, `down`, `demo-1`, `demo-2`, `demo-3`, `reset-jenkins` | Makefile exists. All listed targets exist. `up` target needs to be upgraded to a true one-command bootstrap. `demo-warmup` is not listed in DOCS-04 but is needed per Key Risks. |
| DOCS-05 | `README.md` with quickstart, prerequisites, and link to thesis context | `README.md` does NOT exist. |
</phase_requirements>

---

## Summary

Phase 6 is the final "assembly and packaging" phase. All infrastructure, pipeline, and security components are built and working across Phases 1–5. Phase 6 does not introduce new technical capabilities — it wires existing pieces into runnable demo scenarios, writes the documentation a fresh machine needs to reproduce the demo, and validates the whole system holds together under rehearsal conditions.

The critical finding from auditing the current repo is that **every deliverable in Phase 6 is either entirely missing or incomplete**. The `docs/` directory does not exist. `README.md` does not exist. `app/README.md` does not exist. The `up` Makefile target currently chains only `phase-1` and then prints manual instructions — it is not a true one-command bootstrap as required by INFRA-04.

The three demo Makefile targets (`demo-1`, `demo-2`, `demo-3`) do exist and wire the correct scripts. The primary work for DOCS-04 is upgrading the `up` target and adding a `demo-warmup` target. For DOCS-01 through DOCS-03 and DOCS-05 and APP-05, the work is net-new writing based on the accumulated empirical knowledge from Phases 1–5.

**Primary recommendation:** Treat Phase 6 as three parallel work streams: (A) upgrade Makefile `up` target + add `demo-warmup`, (B) write all docs files from scratch using concrete outputs from prior phases, (C) rehearse the full `make down && make up && make demo-1 && demo-2 && demo-3` cycle and fix any ordering issues found.

---

## Current State Audit

### What Exists (no Phase 6 work needed)

| File/Target | Status | Notes |
|-------------|--------|-------|
| `Makefile` `demo-1` | EXISTS | Calls `ci/tests/scenario-1.sh` |
| `Makefile` `demo-2` | EXISTS | Calls `ci/tests/scenario-2.sh` |
| `Makefile` `demo-3` | EXISTS | Runs all 3 attack scripts + WSL2 log copy-out |
| `Makefile` `down` | EXISTS | Calls registry-stop + teardown-argocd + teardown-falco + jenkins-stop |
| `Makefile` `reset-jenkins` | EXISTS | Calls `ci/jenkins-reset.sh` |
| `Makefile` `status` | EXISTS | Shows cluster/registry/ArgoCD/Falco/Jenkins state |
| `attacks/sqli.py` | EXISTS | Phase 5 artefact |
| `attacks/reverse_shell.sh` | EXISTS | Phase 5 artefact |
| `attacks/privilege_probe.sh` | EXISTS | Phase 5 artefact |
| `falco/values.yaml` | EXISTS | Phase 5 artefact |
| `falco/rules/` | EXISTS | Phase 5 custom rules |

### What Is Missing (Phase 6 must create)

| File | Requirement | Notes |
|------|-------------|-------|
| `docs/` directory | DOCS-01..03 | Entire directory absent |
| `docs/setup.md` | DOCS-01 | Net-new |
| `docs/scenarios.md` | DOCS-02 | Net-new |
| `docs/architecture.md` | DOCS-03 | Net-new; ASCII or Mermaid (see below) |
| `README.md` | DOCS-05 | Net-new |
| `app/README.md` | APP-05 | Net-new; `server.js` has inline vulnerability markers to reference |
| `docs/DEMO-SCRIPT.md` | Not in reqs, referenced in roadmap task list | Thesis committee script; line-by-line with expected outputs |

### What Needs Upgrading (Phase 6 must modify)

| File | Change Needed | Requirement |
|------|---------------|-------------|
| `Makefile` `up` target | Currently only chains `phase-1` + prints instructions. Must chain: phase-1, phase-3 (ArgoCD + Kyverno), phase-4 (Jenkins), phase-5 (Falco) | INFRA-04 |
| `Makefile` | Add `demo-warmup` target: no-op Jenkins build + force Trivy DB download before audience arrives | Key Risk from ROADMAP |

---

## Makefile `up` Target Analysis

### Current Implementation (INCOMPLETE for INFRA-04)

```makefile
up: phase-1
    @echo "✓ Phase 1 complete. Next phases (run in order):"
    @echo "  make phase-2         — build + scan + push demoapp"
    # ... prints manual instructions
```

The current `up` only starts the registry and configures `registries.yaml`. It does not install ArgoCD, Kyverno, Jenkins, or Falco.

### Required Implementation for INFRA-04

INFRA-04 requires: "One-command bootstrap script (`make up`) installs all cluster components from scratch."

The ROADMAP Phase 6 Success Criteria SC-1 states: "`make up` on a machine with only Rancher Desktop installed provisions the full stack in under 15 minutes and exits 0."

**Critical constraint:** Rancher Desktop must be restarted after `configure-registry` writes `registries.yaml`. This step cannot be automated in a Makefile — it requires a human action. The convention is to print a clear STOP instruction and require re-running `make up` after restart, OR to split bootstrap into `make bootstrap` (pre-restart) + `make up` (post-restart full stack).

**Recommended approach:** Preserve the existing `phase-1` through `phase-5` targets (they are used for incremental development and verification). The `up` target should be the orchestration layer that calls them in sequence and handles the one mandatory pause:

```makefile
up: phase-1
    @echo ""
    @echo "ACTION REQUIRED: Restart Rancher Desktop to load registry config."
    @echo "  rdctl shutdown && rdctl start"
    @echo "Then run: make stack"

stack: phase-3 phase-3-apply phase-3-kyverno phase-4 phase-5
    @echo "✓ Full stack bootstrapped. Run: make demo-warmup"
```

This splits the single manual interruption out cleanly. Alternatively, a single `up` that runs everything and SKIPS the RD restart step (since the registry is usually already configured) is also valid — the planner should decide.

### `demo-warmup` Target (needed per Key Risks)

From ROADMAP Phase 6 Key Risk 2: "A fresh `make up` leaves Trivy DB uncached and ArgoCD syncs slow. Add a `make demo-warmup` target that runs a no-op build and forces a Trivy DB download before the audience arrives."

This target does not exist. It should:
1. Trigger a Jenkins build that does nothing (or runs a no-op scan to populate the Trivy DB cache)
2. Check ArgoCD sync status is `Synced`
3. Verify Falco is Running
4. Print "Stack is warm. Demos ready."

---

## Documentation Content Map

### `docs/setup.md` (DOCS-01)

Content that MUST appear (derived from empirical Phase 1–4 findings):

| Section | Content |
|---------|---------|
| Prerequisites | Rancher Desktop 1.23.1 only (no Docker Desktop), Windows 10/11 WSL2, 16 GB RAM recommended, Git |
| RD configuration | Set VM memory to 6 GB minimum in Preferences → Resources |
| Registry setup | `docker run -d --restart=always -p 5001:5000 --name registry registry:2` (port 5001) |
| registries.yaml | Exact contents from `cluster/registries.yaml` (Phase 1 artefact) |
| insecure-registries | `/etc/docker/daemon.json` inside VM via `cluster/insecure-registry.start` provisioning script — `dockerd` engine ignores `registries.yaml` |
| RD restart | `rdctl shutdown && rdctl start` — required after copying `registries.yaml` |
| Verification | `make verify-phase-1` passes; `curl http://localhost:5001/v2/` returns `{}` |
| Jenkins | `make phase-4` — starts at `http://localhost:8080`; no wizard; pre-configured via JCasC |
| Docker socket | On Windows/WSL2: `/var/run/docker.sock` (NOT `~/.rd/docker.sock` which is macOS/lima) |
| Troubleshooting | Top 3 failure modes from accumulated context: (1) registry unreachable — check `insecure-registries`; (2) Falco CrashLoopBackOff — verify BTF exists; (3) Jenkins CSRF on curl — use cookie jar |

### `docs/scenarios.md` (DOCS-02)

Three runbooks. Each runbook needs:
- What the scenario proves (one sentence, for committee slide cues)
- Prerequisites (what must be running)
- Exact commands with expected terminal output snippets
- Timing notes ("wait 30 s for ArgoCD sync", "wait 60 s for Jenkins to boot")
- What to observe in the UI (Jenkins stage view, ArgoCD UI, Falcosidekick webui)
- Pass/fail check

| Scenario | Key Commands | What It Proves |
|----------|-------------|----------------|
| 1 — Blocked Build | `make demo-1` → Jenkins SCAN stage goes red | Trivy shift-left: vulnerable images never reach the registry |
| 2 — Successful Deploy | `make demo-2` → all 4 stages green, ArgoCD syncs | GitOps pipeline end-to-end: code commit → cluster state change |
| 3 — Live Attack | `make demo-3` → Falcosidekick webui shows ≥3 alerts | Runtime detection: attacks trigger named Falco rules within 30 s |

### `docs/architecture.md` (DOCS-03)

Should contain:
1. Component diagram — three security layers (shift-left / GitOps policy / runtime detection)
2. Data flow — Git → Jenkins → Registry → ArgoCD → Cluster → Falco
3. Network topology — host / Rancher Desktop VM / registry / cluster namespace boundaries

**CLAUDE.md already contains an ASCII architecture diagram** (the `Architecture` section with the mono-repo layout). This can be adapted. A fuller diagram showing data flow is needed.

### `README.md` (DOCS-05)

Standard thesis project README pattern:
1. One-liner project description (thesis title)
2. Architecture diagram (ASCII — most portable for GitHub + PDF export)
3. Prerequisites table
4. Quickstart (5 commands: `git clone` + `make up` + `make demo-warmup` + `make demo-1/2/3`)
5. What each demo scenario proves (3 bullets)
6. Links to `docs/setup.md`, `docs/scenarios.md`, `docs/architecture.md`
7. Thesis context (institution, programme, supervisor)

### `app/README.md` (APP-05)

Must document each vulnerability with OWASP 2021 reference. Content available from `app/server.js`:

| Endpoint | Vulnerability | OWASP 2021 |
|----------|--------------|-----------|
| `GET /sqli?user=` | String-concatenated SQL query, no parameterisation. Vulnerable line: `const query = "SELECT * FROM users WHERE id = '" + user + "'"` | A03:2021 Injection |
| `GET /cmd?input=` | `child_process.exec` with unvalidated `input` parameter. Vulnerable line: `exec(input, ...)` | A03:2021 Injection (OS Command Injection) |
| Base image | `node:14.0.0-alpine` (or pinned old digest) — guarantees HIGH/CRITICAL Trivy findings | A06:2021 Vulnerable and Outdated Components |
| Root user | No `USER` directive in Dockerfile — container runs as root | A05:2021 Security Misconfiguration |

---

## Architecture Diagram Strategy

### Problem

The thesis committee will view the demo on screen and may export documentation to Word/PDF. Mermaid diagrams:
- Render natively on GitHub (HIGH value for committee browsing the repo)
- Require a Mermaid renderer in Word/PDF (does NOT render in raw PDF export)
- ASCII diagrams render everywhere — terminal, GitHub, Word, PDF

### Recommendation (HIGH confidence)

Use **both**, serving different purposes:

| File | Diagram Type | Why |
|------|-------------|-----|
| `README.md` | ASCII art | Universal portability; renders in PDF, terminal, GitHub |
| `docs/architecture.md` | Mermaid `flowchart LR` | Native GitHub rendering; richer visual for committee browsing repo |

The CLAUDE.md has an ASCII structure diagram already. For `docs/architecture.md`, a Mermaid flowchart showing the three-layer security control flow is more expressive:

```
flowchart LR
    DEV[Developer\nPush] --> GIT[Git Repo]
    GIT --> JENKINS[Jenkins CI\nTrivy SCAN]
    JENKINS -->|CVE found| BLOCK[Build Blocked\nno push]
    JENKINS -->|clean| REG[Local Registry\nlocalhost:5001]
    REG --> ARGO[ArgoCD\nauto-sync]
    ARGO --> KYV[Kyverno\nadmission control]
    KYV -->|policy denied| DENY[Manifest Blocked]
    KYV -->|policy allowed| CLUSTER[k3s Cluster\ndemoapp ns]
    CLUSTER --> FALCO[Falco\nmodern_ebpf]
    ATK[Attack Scripts] --> CLUSTER
    FALCO -->|alert| SIDEKICK[Falcosidekick\nwebui + file]
```

---

## DEMO-SCRIPT.md Content Pattern

The roadmap task list (Task 6 in Phase 6) mentions `docs/DEMO-SCRIPT.md` — a line-by-line thesis committee demo script. This is not in the formal requirements (DOCS-01..05 cover other files) but is a high-value deliverable for the defence.

**Recommended format for a Bulgarian university defence:**

```markdown
# Demo Script — Thesis Committee Presentation

**Total demo time:** ~15 minutes
**Setup:** Must run `make demo-warmup` before the committee sits down.

---

## Scenario 1: Shift-Left Security (Trivy) [~4 minutes]

**Say:** "The first layer blocks vulnerable images before they ever touch the cluster."

1. Open Jenkins at http://localhost:8080
2. Run: `make demo-1`
3. **Wait:** ~90 seconds for Jenkins to start the build
4. **Point at:** SCAN stage going red
5. **Say:** "Trivy detected [N] HIGH/CRITICAL CVEs. The PUSH stage never ran."
6. **Show:** `curl http://localhost:5001/v2/demoapp/tags/list` — old tag, no new tag

---
```

Each scenario block should contain: what to say, exact commands, what to point at, expected output snippet, timing, and a fallback note if the live demo fails.

---

## Common Pitfalls for Phase 6

### Pitfall 1: `up` target assumes RD is already configured
**What goes wrong:** Running `make up` on a fresh machine fails silently after Phase 1 because the RD restart step is skipped.
**Prevention:** Add an explicit STOP in the `up` output with `rdctl shutdown && rdctl start` instruction. Consider a `make bootstrap` / `make stack` split.

### Pitfall 2: RAM blowout during demo rehearsal
**What goes wrong:** Running `demo-2` (Jenkins build) and `demo-3` (attack + Falco) back-to-back without waiting for Jenkins to finish pushes RAM over 10 GB, causing `CrashLoopBackOff` cascades.
**Prevention:** `demo-3` Makefile target should check that no Jenkins build is running before invoking attack scripts. Document in `docs/scenarios.md`: "Always wait for `demo-2` to complete before starting `demo-3`."

### Pitfall 3: Trivy DB cold on fresh `make up`
**What goes wrong:** First `demo-1` run after fresh bootstrap takes 3–5 minutes for Trivy DB download, looks broken to the committee.
**Prevention:** `make demo-warmup` target forces a Trivy DB pull before the audience arrives.

### Pitfall 4: WSL2 log copy-out fails on demo machine
**What goes wrong:** `wsl -d rancher-desktop -- cat /var/log/falco/events.log` fails with "distribution not found" on some Windows configurations.
**Prevention:** `demo-3` already has `|| echo "(run copy-out manually)"` fallback. `docs/scenarios.md` should document the manual fallback: `wsl -d rancher-desktop` vs direct `kubectl exec` into Falcosidekick pod.

### Pitfall 5: Port-forward drops during demo-3 live display
**What goes wrong:** `kubectl port-forward` for Falcosidekick webui silently dies during attack simulation, leaving audience with a blank browser.
**Prevention:** `docs/DEMO-SCRIPT.md` should note: start port-forward in a separate terminal window _after_ attack scripts finish (or use `nohup`). File output is the primary evidence; webui is secondary.

### Pitfall 6: Timezone mismatch in logs
**What goes wrong:** Falco alert timestamps differ by hours from host timestamps, confusing the committee.
**Prevention:** Verify all containers have `TZ=UTC`. Document in `docs/setup.md`.

### Pitfall 7: README.md ASCII diagram is stale vs actual topology
**What goes wrong:** README written before Phase 5 uses port 5000 or old architecture details.
**Prevention:** Write README.md LAST, after all phases are verified. Cross-check every port and hostname against the current Makefile and `demoapp-patch.yaml` (which confirms `host.rancher-desktop.internal:5001`).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Architecture diagram | Custom SVG/image | Mermaid in `.md` | Renders in GitHub, version-controlled, no binary assets |
| Demo timing | Custom sleep-and-poll script | Existing verify scripts (`verify-phase-4`, `verify-phase-5`) | Scripts already encode the correct poll logic |
| OWASP references | Custom vulnerability DB | Link to owasp.org/Top10/A03_2021-Injection | Official source, always current |

---

## Environment Availability

Step 2.6: SKIPPED — Phase 6 is entirely documentation, Makefile editing, and rehearsal. No new external dependencies beyond what Phases 1–5 already required. All tools (helm, kubectl, docker, wsl) are already verified by prior phases.

---

## Validation Architecture

The validation model for Phase 6 is rehearsal-based, not unit-test-based. The Success Criteria from ROADMAP are acceptance tests runnable as Makefile targets.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Command | Status |
|--------|----------|-----------|---------|--------|
| INFRA-04 | `make up` exits 0, full stack running | smoke | `make up && make status` | Manual — requires Windows target |
| APP-05 | `app/README.md` exists with OWASP refs | manual | file review | Wave 0: file must be created |
| DEMO-01 | `demo-1` produces red SCAN stage, no new image tag | acceptance | `make demo-1` | Script exists; docs pending |
| DEMO-02 | `demo-2` produces green pipeline + ArgoCD sync | acceptance | `make demo-2` | Script exists; docs pending |
| DEMO-03 | `demo-3` triggers ≥3 Falco alerts within 30 s | acceptance | `make demo-3` | Script exists; docs pending |
| DOCS-01 | `docs/setup.md` exists and commands are accurate | manual | dry-run on clean machine | Net-new |
| DOCS-02 | `docs/scenarios.md` contains exact commands | manual | dry-run | Net-new |
| DOCS-03 | `docs/architecture.md` has component diagram | manual | file review | Net-new |
| DOCS-04 | Makefile has `up`, `down`, `demo-1/2/3`, `reset-jenkins` | smoke | `make --dry-run up` etc. | Mostly exists; `up` needs upgrade |
| DOCS-05 | `README.md` exists with quickstart | manual | file review | Net-new |

### Wave 0 Gaps

- [ ] `docs/` directory — must be created
- [ ] `docs/setup.md` — net-new
- [ ] `docs/scenarios.md` — net-new
- [ ] `docs/architecture.md` — net-new
- [ ] `docs/DEMO-SCRIPT.md` — net-new (not a formal req but high value)
- [ ] `README.md` — net-new
- [ ] `app/README.md` — net-new
- [ ] Makefile `up` target — upgrade to call all phases in sequence
- [ ] Makefile `demo-warmup` target — add

---

## Code Examples

### Existing `demo-3` Makefile target (Phase 5 artefact, works)

```makefile
demo-3:
    @echo "── Demo Scenario 3: Live Attack Detected ────────────────────────────────────"
    @python3 attacks/sqli.py || true
    @bash attacks/reverse_shell.sh || true
    @bash attacks/privilege_probe.sh || true
    @echo ""
    @echo "Copying Falco alert log out of the WSL2 VM..."
    -@wsl -d rancher-desktop cat /var/log/falco/events.log > logs/falco.log 2>/dev/null || echo "  (run copy-out manually)"
    @echo "Check Falco alerts:"
    @echo "  Logs: kubectl logs -f -n falco -l app.kubernetes.io/name=falco"
    @echo "  UI:   kubectl port-forward svc/falco-falcosidekick-ui -n falco 2802:2802"
    @echo "  File: tail -20 logs/falco.log"
```

### Recommended `up` upgrade pattern

```makefile
up: phase-1
    @echo ""
    @echo "══════════════════════════════════════════════════════════"
    @echo "  ACTION REQUIRED: Restart Rancher Desktop to apply"
    @echo "  the registry config written to ~/.rd/k3s/registries.yaml"
    @echo ""
    @echo "  Run:  rdctl shutdown && rdctl start"
    @echo "  Wait: ~60 s for Kubernetes: Running"
    @echo "  Then: make stack"
    @echo "══════════════════════════════════════════════════════════"

stack: phase-3 phase-3-apply phase-3-kyverno phase-4 phase-5
    @echo "✓ Full stack bootstrapped."
    @echo "  Run: make demo-warmup   (warms Trivy DB before demo)"
    @echo "  Run: make demo-1 / demo-2 / demo-3"
```

### `demo-warmup` target pattern

```makefile
demo-warmup:
    @echo "── Warming demo stack ────────────────────────────────────────────────"
    @echo "Step 1/3: Check cluster is healthy"
    @kubectl get nodes --no-headers | grep -q Ready || (echo "✗ k3s not ready"; exit 1)
    @echo "Step 2/3: Check ArgoCD is Synced"
    @kubectl get application -n argocd demoapp -o jsonpath='{.status.sync.status}' | grep -q Synced || echo "  (ArgoCD not yet synced — may take 30 s)"
    @echo "Step 3/3: Pre-warm Trivy DB (runs a scan against fixed image)"
    @docker run --rm -v "$$HOME/.trivy-cache:/root/.cache/trivy" aquasec/trivy:v0.72.0 \
        image --download-db-only --db-repository public.ecr.aws/aquasecurity/trivy-db 2>&1 | tail -3
    @echo "✓ Stack warm. Ready for demo."
```

### `app/README.md` structure

```markdown
# demoapp — Intentionally Vulnerable Demo Application

This application is deliberately insecure for thesis demonstration purposes.
It MUST NOT be deployed outside a local, isolated environment.

## Vulnerabilities

### OWASP A03:2021 — Injection (SQL Injection)
- Endpoint: `GET /sqli?user=<input>`
- Vulnerable code (`server.js`): `const query = "SELECT * FROM users WHERE id = '" + user + "'"`
- Attack: `curl "http://localhost:<port>/sqli?user=' OR '1'='1"`

### OWASP A03:2021 — Injection (OS Command Injection)
- Endpoint: `GET /cmd?input=<input>`
- Vulnerable code (`server.js`): `exec(input, { timeout: 5000 }, ...)`
- Attack: `curl "http://localhost:<port>/cmd?input=id"`

### OWASP A06:2021 — Vulnerable and Outdated Components
- Dockerfile pins an outdated base image (`node:14.0.0-alpine`)
- Trivy reports HIGH/CRITICAL CVEs on every build scan

### OWASP A05:2021 — Security Misconfiguration
- No `USER` directive in Dockerfile; container runs as root
- Demonstrated by: `kubectl exec <pod> -- whoami` → `root`
```

---

## Open Questions

1. **Phase 5 human checkpoint status**
   - What we know: Plans 05-01 and 05-02 are complete. Plan 05-03 Task 3 (human-verify on Windows target) is pending as of 2026-08-28.
   - What's unclear: Whether Phase 5 is verified complete before Phase 6 planning begins.
   - Recommendation: Phase 6 planning should proceed. The DEMO-SCRIPT.md and `docs/scenarios.md` can be written against known-good outputs from Phase 5. If Phase 5 verification reveals issues, attack script commands in docs may need minor updates.

2. **`make up` split strategy**
   - What we know: Rancher Desktop restart is a mandatory manual step that cannot be automated.
   - What's unclear: Whether to split into `make bootstrap` + `make stack`, or use a single `up` with an explicit pause message.
   - Recommendation: Single `up` that outputs the STOP instruction and instructs user to run `make stack` next. Keeps the target name matching DOCS-04 requirement (`make up`) while being honest about the manual step.

3. **`docs/DEMO-SCRIPT.md` scope**
   - What we know: Phase 6 Task 6 in ROADMAP mentions it explicitly. It is not in the formal requirement IDs (DOCS-01..05).
   - What's unclear: Whether it is an explicit deliverable the planner should task or a bonus item.
   - Recommendation: Include as an explicit task in the plan. A thesis defence without a prepared script is a significant risk. Low cost (< 1 hour) for high value.

---

## Sources

### Primary (HIGH confidence)
- Direct file inspection: `Makefile` — full audit of all existing targets
- Direct file inspection: `app/server.js` — vulnerability code confirmed
- Direct file inspection: `.planning/REQUIREMENTS.md` — req IDs, status, and descriptions
- Direct file inspection: `.planning/ROADMAP.md` — Phase 6 tasks, success criteria, key risks
- Direct file inspection: `.planning/STATE.md` — accumulated empirical findings from Phases 1–4
- Direct file inspection: `.planning/research/SUMMARY.md` — confirmed stack versions and pitfalls
- Direct file inspection: `deploy/overlays/local/demoapp-patch.yaml` — confirms registry port 5001
- Direct directory scan: `docs/` does not exist; `README.md` does not exist; `app/README.md` does not exist

### Secondary (MEDIUM confidence)
- ROADMAP Phase 6 Key Risks — pitfall analysis around RAM, cold caches, and timezone; based on prior empirical Phase 1–4 work

### Tertiary (LOW confidence)
- None required — all findings are from direct repo inspection

---

## Metadata

**Confidence breakdown:**
- Current file/directory state: HIGH — direct filesystem inspection
- Makefile target analysis: HIGH — code read directly
- Documentation content recommendations: HIGH — derived from accumulated empirical context (STATE.md Phase 1–4 findings)
- Architecture diagram format recommendation: MEDIUM — based on known Mermaid GitHub support and ASCII portability

**Research date:** 2026-08-31
**Valid until:** Phase 6 start (findings are repo-state facts, not external tool versions)

---

## RESEARCH COMPLETE
