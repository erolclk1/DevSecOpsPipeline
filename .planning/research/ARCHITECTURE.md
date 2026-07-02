# Architecture Patterns

**Domain:** Locally-runnable DevSecOps CI/CD pipeline (thesis project)
**Researched:** 2026-07-02
**Overall confidence:** MEDIUM-HIGH (based on well-established patterns for the fixed toolchain; web verification unavailable in this session)

---

## 1. High-Level Component Diagram

```
                         DEVELOPER LAPTOP (macOS / Linux, 16 GB RAM)
  ┌─────────────────────────────────────────────────────────────────────────────┐
  │                                                                             │
  │   HOST NAMESPACE                                                            │
  │   ┌───────────────────────┐        ┌─────────────────────────────────┐      │
  │   │ Git repo (local)      │◄──────►│ Jenkins (Docker container)      │      │
  │   │  - app/               │  poll  │  - Jenkinsfile pipeline         │      │
  │   │  - deploy/            │        │  - docker build                 │      │
  │   │  - Jenkinsfile        │        │  - trivy image (CLI)            │      │
  │   └───────────────────────┘        │  - docker push  ──────────┐     │      │
  │            ▲                       │  - yq/sed manifest bump   │     │      │
  │            │ commit                │  - git push (deploy dir)  │     │      │
  │            │ (manifest             └────────────────┬──────────┘     │      │
  │            │  bump by CI)                           │                │      │
  │            │                                        ▼                ▼      │
  │            │                          ┌─────────────────────────────────┐   │
  │            │                          │ Local Docker Registry           │   │
  │            │                          │   registry:2 on host :5000      │   │
  │            │                          │   Reachable as:                 │   │
  │            │                          │     host          → localhost   │   │
  │            │                          │     cluster nodes → k3d-registry│   │
  │            │                          │                     .localhost  │   │
  │            │                          └────────────────┬────────────────┘   │
  │            │                                           │ image pull         │
  │   ┌────────┴─────────────────────────────────────────  ▼ ─────────┐         │
  │   │                     K3S CLUSTER  (k3d or Rancher Desktop)     │         │
  │   │                                                               │         │
  │   │   ┌────────────────────┐         ┌────────────────────────┐   │         │
  │   │   │  argocd namespace  │  watch  │  demoapp namespace     │   │         │
  │   │   │  ArgoCD server ────┼────────►│  Deployment            │   │         │
  │   │   │  Repo server       │ create/ │  Service               │   │         │
  │   │   │  Application CRD   │  sync   │  ConfigMap / Secret    │   │         │
  │   │   └─────────┬──────────┘         └──────────┬─────────────┘   │         │
  │   │             │ git pull (deploy/)            │ syscalls        │         │
  │   │             ▼                               ▼                 │         │
  │   │   ┌────────────────────┐         ┌────────────────────────┐   │         │
  │   │   │  Git repo (host,   │         │  falco namespace       │   │         │
  │   │   │  mounted / http)   │         │  Falco DaemonSet       │   │         │
  │   │   └────────────────────┘         │   modern_ebpf driver   │   │         │
  │   │                                  │  Falcosidekick Deploy  │   │         │
  │   │                                  │   → stdout + file      │   │         │
  │   │                                  │   → optional webhook   │   │         │
  │   │                                  └──────────┬─────────────┘   │         │
  │   └─────────────────────────────────────────────┼─────────────────┘         │
  │                                                 │ alert log                 │
  │                                                 ▼                           │
  │                                       ┌───────────────────────┐             │
  │                                       │ ./logs/falco.log      │             │
  │                                       │ (host-mounted volume) │             │
  │                                       └───────────────────────┘             │
  │                                                                             │
  │   ┌───────────────────────┐                                                 │
  │   │ Attack scripts        │ HTTP / TCP  →  demoapp Service (NodePort)       │
  │   │  attacks/*.sh|py      │                                                 │
  │   └───────────────────────┘                                                 │
  └─────────────────────────────────────────────────────────────────────────────┘
```

### Component Boundaries

| Component | Runs Where | Responsibility | Talks To |
|-----------|-----------|----------------|----------|
| Git repo | Host filesystem | Source of truth for code + manifests | Jenkins (polls), ArgoCD (pulls `deploy/`) |
| Jenkins | Host Docker container | Build, scan, push, bump manifest, git push | Docker daemon, Trivy CLI, local registry, Git |
| Trivy | Ephemeral in Jenkins step | Static image scan; fail pipeline on HIGH/CRITICAL | Local registry (or local image cache) |
| Local Docker registry | Host Docker container | Store built images; reachable from both host and cluster | Jenkins (push), k3s nodes (pull) |
| k3s cluster | Rancher Desktop VM or k3d containers | Kubernetes control plane + workloads | Local registry, Git repo |
| ArgoCD | `argocd` namespace | Watch Git `deploy/`, sync manifests into cluster | Git repo, kube-apiserver |
| Demo app | `demoapp` namespace | Vulnerable REST API target for attacks | SQLite (in-pod) or PostgreSQL (sidecar/Deployment) |
| Falco | `falco` namespace, DaemonSet | Runtime syscall detection with custom rules | Node kernel via eBPF; Falcosidekick |
| Falcosidekick | `falco` namespace, Deployment | Fan-out alerts (stdout/file/webhook/UI) | Falco, host-mounted log file |
| Attack scripts | Host shell | Trigger SQLi / port scan / reverse shell against demoapp | demoapp Service (NodePort/port-forward) |

---

## 2. Recommended Git Repo Strategy

**Recommendation: Single mono-repo with clear internal boundaries.** (Confidence: HIGH for this thesis scope)

### Why not classic two-repo GitOps

The canonical GitOps pattern (app-repo + config-repo) exists to prevent CI from creating deploy churn in the app history and to allow different RBAC per repo. For a **single-developer, single-cluster, thesis-scale** project both concerns are absent, and a mono-repo:

- Lets one `git clone` reproduce the entire thesis artifact for the reviewer.
- Keeps documentation, scripts, and manifests aligned to a single commit hash.
- Removes the pain of cross-repo PR coordination during demo rehearsal.

### How to preserve the GitOps property inside one repo

Point ArgoCD at a **specific subdirectory** (`deploy/overlays/local/`) rather than the repo root. The Jenkins pipeline commits only to that subdirectory (a manifest image-tag bump). This gives you:

- A visible "GitOps commit" in the log (e.g. `ci: bump demoapp to sha-abc123`) that reviewers can point to.
- ArgoCD only reacts to changes under `deploy/`; app-code commits do not trigger sync churn.
- The reviewer sees the entire dataflow in one `git log`.

### When to reconsider

Split into two repos only if:
- Committee later requires demonstrating separation-of-duties / RBAC across teams.
- You add a second target environment and want independent promotion history.

---

## 3. Recommended Folder Structure

```
myProject/
├── README.md                       # Thesis quickstart, demo scenarios
├── docs/
│   ├── architecture.md             # This diagram, exported for thesis
│   ├── setup.md                    # Step-by-step bootstrap
│   ├── scenarios.md                # 3 demo runbooks (blocked/deploy/attack)
│   └── thesis/                     # Chapter drafts, figures
│
├── app/                            # Vulnerable demo application
│   ├── src/                        # Node.js (Express) or Python (Flask/FastAPI)
│   ├── tests/                      # Minimal unit tests, run in CI
│   ├── Dockerfile                  # Multi-stage; pin base image digest
│   ├── .dockerignore
│   └── package.json | pyproject.toml
│
├── ci/                             # Jenkins configuration-as-code
│   ├── Jenkinsfile                 # Declarative pipeline (root reference too)
│   ├── jcasc/
│   │   └── jenkins.yaml            # JCasC: credentials, jobs, tools
│   ├── docker/
│   │   ├── Dockerfile              # Jenkins image + docker CLI + trivy + yq
│   │   └── plugins.txt
│   └── scripts/
│       ├── trivy-scan.sh           # Wrapped scan step (severity, exit codes)
│       └── bump-manifest.sh        # yq write + git commit + git push
│
├── deploy/                         # Everything ArgoCD watches
│   ├── argocd/
│   │   ├── install/                # ArgoCD bootstrap manifests (one-time)
│   │   └── applications/
│   │       ├── demoapp.yaml        # ArgoCD Application CRD
│   │       └── falco.yaml          # ArgoCD Application for Falco (optional)
│   ├── base/
│   │   ├── demoapp/                # Kustomize base: Deployment, Service, CM
│   │   └── falco/                  # Falco Helm values or raw manifests
│   └── overlays/
│       └── local/                  # Overlay ArgoCD points at
│           ├── kustomization.yaml
│           ├── demoapp-patch.yaml  # Image tag lives here (CI bumps this)
│           └── namespace.yaml
│
├── falco/                          # Custom rules + sidekick config
│   ├── rules/
│   │   ├── reverse_shell.yaml
│   │   ├── suspicious_process.yaml
│   │   └── demoapp_specific.yaml   # Rules scoped by k8s labels
│   └── falcosidekick-values.yaml   # Outputs: stdout + file + optional webhook
│
├── registry/                       # Local registry helpers
│   ├── docker-compose.yaml         # registry:2 on :5000
│   └── k3d-registry-config.yaml    # registries.yaml injected into k3d
│
├── cluster/                        # Cluster bootstrap
│   ├── k3d-config.yaml             # OR rancher-desktop notes
│   └── bootstrap.sh                # Install argocd + falco + apps
│
├── attacks/                        # Attack simulation scripts
│   ├── sqli.py                     # SQL injection against demoapp
│   ├── portscan.sh                 # nmap against Service ClusterIP
│   ├── reverse_shell.sh            # Trigger via app RCE / kubectl exec
│   └── README.md                   # Which rule each attack fires
│
├── logs/                           # Host-mounted Falco alert sink (gitignored)
│   └── .gitkeep
│
├── Makefile                        # up / down / demo-* targets
└── .gitignore
```

### Rationale

- **`deploy/` is the GitOps boundary.** ArgoCD points at `deploy/overlays/local/`. Everything else can change without touching the cluster.
- **`ci/` isolates Jenkins concerns.** JCasC yaml, plugins.txt, and the pipeline Dockerfile stay together so `docker compose up jenkins` is reproducible.
- **`attacks/` beside `falco/`** makes the mapping "attack → rule" reviewable in one glance for the thesis defense.
- **`registry/` and `cluster/`** are one-time bootstrap helpers, kept out of `deploy/` so ArgoCD does not touch them.
- **Kustomize over raw manifests** in `deploy/` — the manifest bump becomes a single-line patch update, which is trivial to script and to show in `git diff`.

---

## 4. Network Topology & Registry Reachability

The single hardest local-DevSecOps issue is: **the same image name must resolve to the same registry from both Jenkins (host) and the k3s nodes (VM/containers).** Solve this once, up front.

### Recommended approach (Confidence: HIGH)

Use **k3d's built-in registry integration** and reference the image by the k3d registry hostname everywhere:

```
Registry name inside cluster:  k3d-registry.localhost:5000
Registry name on host:         k3d-registry.localhost:5000   (via /etc/hosts → 127.0.0.1)
```

Steps:

1. Create the registry with k3d: `k3d registry create registry.localhost --port 5000`.
2. Create the cluster with k3d, attaching the registry: `k3d cluster create dev --registry-use k3d-registry.localhost:5000 --config cluster/k3d-config.yaml`.
3. Add `127.0.0.1 k3d-registry.localhost` to `/etc/hosts` on the host so Jenkins can `docker push` to the same name.
4. In `app/Dockerfile`-produced tags and in `deploy/overlays/local/demoapp-patch.yaml`, always use `k3d-registry.localhost:5000/demoapp:<sha>`.

Result: **no IP juggling, no insecure-registries mtn on the host Docker daemon**, and the exact same image reference is valid in both `docker push` and the Kubernetes `Deployment` spec.

### If using Rancher Desktop instead of k3d

Rancher Desktop's k3s VM cannot resolve `localhost` on the host. Two options:

- **Preferred:** Bind the registry to `host.rancher-desktop.internal` (analogous to `host.docker.internal`) and register it via `/etc/rancher/k3s/registries.yaml` inside the VM. Rancher Desktop supports mounting this file.
- **Fallback:** Use the k3d approach even under Rancher Desktop by running k3d containers instead of the built-in k3s — this is why the PROJECT.md decision favors k3d for the registry path.

### Traffic paths

```
Jenkins  ──docker push──►  k3d-registry.localhost:5000     (host loopback)
kubelet  ──image pull──►   k3d-registry.localhost:5000     (via registries.yaml)
ArgoCD   ──git pull──►     file:// or http://host-git       (repo-server clone)
Attacker ──HTTP──►         k3d LoadBalancer / NodePort → demoapp Service
```

---

## 5. Data Flow: Commit → Detected Attack

```
[1] Developer                git commit + git push        (app/**)
        │
        ▼
[2] Jenkins polls Git ─── or webhook (localhost forwarded) ─── build triggers
        │
        ▼
[3] Jenkins stage: BUILD    docker build -t k3d-registry.localhost:5000/demoapp:<sha> app/
        │
        ▼
[4] Jenkins stage: SCAN     trivy image --severity HIGH,CRITICAL --exit-code 1 <img>
        │                    ├── FAIL → pipeline red, image NOT pushed  ◄── Scenario 1
        │                    └── PASS ▼
        │
[5] Jenkins stage: PUSH     docker push k3d-registry.localhost:5000/demoapp:<sha>
        │
        ▼
[6] Jenkins stage: BUMP     yq eval '.spec.template.spec.containers[0].image = ...'
                            deploy/overlays/local/demoapp-patch.yaml
                            git add + commit "ci: bump demoapp to <sha>" + git push
        │
        ▼
[7] ArgoCD (3-min poll or webhook) detects deploy/ change
        │
        ▼
[8] ArgoCD sync             kubectl apply of rendered kustomize output
        │                                                                ◄── Scenario 2
        ▼
[9] kubelet pulls           k3d-registry.localhost:5000/demoapp:<sha>
        │
        ▼
[10] Pod running            demoapp exposes REST API via Service/NodePort
        │
        ▼
[11] Attacker runs          python attacks/sqli.py http://localhost:<nodeport>/
        │
        ▼
[12] Container syscalls     execve, connect, open ── observed by Falco eBPF probe
        │
        ▼
[13] Falco matches rule     falco/rules/*.yaml (e.g. "Reverse shell in container")
        │
        ▼
[14] Falcosidekick outputs  stdout (kubectl logs) + file mount (./logs/falco.log)
                                                                          ◄── Scenario 3
```

### Where each control layer proves itself

| Layer | Control | Proven by |
|-------|---------|-----------|
| Shift-left | Trivy in step [4] blocks vulnerable base image | Scenario 1: red Jenkins run, no image pushed |
| GitOps policy | ArgoCD only syncs signed manifest commits from `deploy/` | Scenario 2: manual `kubectl apply` outside Git is reverted by self-heal |
| Runtime | Falco DaemonSet + custom rules | Scenario 3: attack script → matching alert line in `./logs/falco.log` |

---

## 6. Falco Alert Surfacing

**Recommendation:** Falco → Falcosidekick → **stdout + file output** (Confidence: HIGH)

### Rationale

For a thesis defense you need alerts that are:
- Visible live during the demo (stdout via `kubectl logs -f`).
- Persisted for the written thesis screenshots (file on host).
- Easy to reason about — no external SaaS, no email, no Slack tokens.

### Configuration sketch

```yaml
# falco/falcosidekick-values.yaml
falcosidekick:
  config:
    debug: true
    stdout:
      minimumpriority: "notice"
    webhook:
      # Optional: point to a small Python HTTP receiver in attacks/ for JSON demos
      address: ""
  webui:
    enabled: true       # Cheap dashboard for defense demo (falcosidekick-ui)

falco:
  driver:
    kind: modern_ebpf   # REQUIRED on Rancher Desktop (see PROJECT.md)
  falcosidekick:
    enabled: true
  extra:
    args: []
  # Mount host path for a durable alert log
  extraVolumes:
    - name: alertlog
      hostPath: { path: /host/logs, type: DirectoryOrCreate }
  extraVolumeMounts:
    - name: alertlog
      mountPath: /var/log/falco
  file_output:
    enabled: true
    keep_alive: false
    filename: /var/log/falco/events.log
```

### Alternatives considered

| Sink | Why not (for this project) |
|------|----------------------------|
| Slack / Teams webhooks | Requires external network + tokens; adds no thesis value |
| Prometheus / Loki stack | Doubles the RAM budget; steady-state 8-10 GB is already the ceiling |
| stdout only (no sidekick) | Loses the "one JSON per line" file that's ideal for screenshots |
| Custom log tailer script | Reinvents Falcosidekick without gain |

The optional `falcosidekick-ui` deployment is worth the ~150 MB RAM for a live-updating alert list on the defense laptop, but keep it toggleable.

---

## 7. Component Build / Setup Order

Order is chosen so each step is **testable in isolation** before adding the next dependency.

| # | Step | Deliverable / verification |
|---|------|----------------------------|
| 0 | Prereqs: Docker, k3d, kubectl, git, yq, trivy CLI on host | `docker version && k3d version && kubectl version --client` |
| 1 | Local Docker registry via k3d + `/etc/hosts` entry | `curl http://k3d-registry.localhost:5000/v2/` returns `{}` |
| 2 | k3s cluster via k3d config referencing the registry | `kubectl get nodes` shows Ready; `k3d image import` works |
| 3 | Demo app skeleton + Dockerfile builds locally | `docker build && docker run` returns 200 on `GET /` |
| 4 | Push to local registry, deploy via **raw `kubectl apply`** | Pod pulls image, Service reachable from host |
| 5 | Install ArgoCD in cluster (`deploy/argocd/install/`) | ArgoCD UI reachable via port-forward |
| 6 | Register ArgoCD Application pointing at `deploy/overlays/local/` | Manual git edit → auto-sync visible in UI |
| 7 | Jenkins container with JCasC + Dockerfile-baked trivy | Jenkins boots with pipeline job pre-configured |
| 8 | Jenkinsfile stages: build → scan → push → bump manifest | End-to-end run: green pipeline → new pod version |
| 9 | Deliberately introduce vulnerable base image | Scenario 1 verified: pipeline blocks, no push |
| 10 | Install Falco via Helm (`modern_ebpf`) + Falcosidekick | `kubectl logs falco-*` shows startup, no errors |
| 11 | Add custom rules under `falco/rules/` | Rule syntax validated by Falco on load |
| 12 | Attack scripts + host-mounted alert log | Scenario 3 verified: attack fires named rule to file |
| 13 | Documentation, Makefile targets, README quickstart | Fresh clone → `make up && make demo-1/2/3` works |

**Critical rule:** do not touch Jenkins (step 7) before ArgoCD + manual deploy (steps 5-6) work. Jenkins is the highest-risk component per PROJECT.md; you want a working deploy path to observe when Jenkins first tries to bump a manifest.

---

## 8. Patterns to Follow

### Pattern 1: Immutable image tags (never `latest`)
**What:** Every build tags the image with the git short SHA.
**When:** Always; enforced by `bump-manifest.sh` writing the same SHA into the manifest.
**Why:** ArgoCD only detects change when the manifest changes; a moving `latest` tag breaks GitOps semantics entirely.

### Pattern 2: ArgoCD sub-path, not repo root
**What:** ArgoCD `Application.spec.source.path = deploy/overlays/local`.
**Why:** Keeps app-code commits from causing ArgoCD sync noise; supports mono-repo.

### Pattern 3: Kustomize patch for the image line only
**What:** CI touches exactly one YAML key: the container image.
**Example:**
```yaml
# deploy/overlays/local/demoapp-patch.yaml (post-CI)
apiVersion: apps/v1
kind: Deployment
metadata: { name: demoapp }
spec:
  template:
    spec:
      containers:
        - name: demoapp
          image: k3d-registry.localhost:5000/demoapp:abc1234
```
**Why:** `git diff` after CI is one line; extremely legible in the thesis writeup.

### Pattern 4: Falco rules scoped by k8s labels
**What:** Rule conditions include `k8s.ns.name = "demoapp"` or a pod label match.
**Why:** Prevents false positives from `kube-system`, `argocd`, and the Jenkins container itself.

### Pattern 5: JCasC + baked-in tooling in Jenkins Dockerfile
**What:** Jenkins image installs `docker`, `trivy`, `yq`, `git`, `kubectl` at build time.
**Why:** Avoids the "install-tool-on-first-run" pitfall in Jenkins agents; pipeline stays declarative.

---

## 9. Anti-Patterns to Avoid

### AP1: Referencing the registry by IP address
**Why bad:** IPs change (`k3d cluster restart`, laptop DHCP). Manifests and Jenkins credentials break.
**Instead:** Use `k3d-registry.localhost` everywhere; put it in `/etc/hosts`.

### AP2: Letting Jenkins `kubectl apply` directly
**Why bad:** Bypasses the entire GitOps demonstration; ArgoCD becomes decoration.
**Instead:** Jenkins only touches Git; ArgoCD touches the cluster.

### AP3: Running Falco with `driver.kind: kmod`
**Why bad:** PROJECT.md already flags this — Rancher Desktop VM lacks kernel headers.
**Instead:** `driver.kind: modern_ebpf`, verified in Falco 0.36+.

### AP4: Two separate repos before you have the first pipeline green
**Why bad:** Doubles the coordination cost during the fragile bootstrap phase.
**Instead:** Mono-repo with an ArgoCD sub-path; split later only if a reviewer demands it.

### AP5: Trivy as a Jenkins plugin
**Why bad:** PROJECT.md decision — plugin hides the CLI invocation you want to show in screenshots.
**Instead:** Shell step calling `trivy image` with explicit flags.

### AP6: SQLite baked into the image for the "database" tier
**Why bad:** Removes an interesting attack surface and any lateral-movement demo.
**Instead:** PostgreSQL as a separate Deployment in the same namespace — enables a "credential access" attack scenario Falco can catch.

---

## 10. Scalability & Resource Considerations

Thesis-scale, so "scalability" here means **staying inside the 16 GB laptop budget**.

| Component | Steady-state RAM (est.) | Notes |
|-----------|-------------------------|-------|
| Rancher Desktop / k3d VM | 1.5-2 GB | Base cluster + system pods |
| ArgoCD (server+repo+app+redis+dex) | 500-800 MB | Disable `dex` and `notifications-controller` if tight |
| Falco DaemonSet | 250-400 MB | modern_ebpf is lighter than kmod |
| Falcosidekick + UI | 100-200 MB | UI is optional |
| Jenkins container | 1-1.5 GB | Give `-Xmx1g` explicitly |
| Local registry | 50-100 MB | Cleanup old tags periodically |
| Demo app pod(s) | 100-200 MB | Node/Python + Postgres sidecar |
| Docker daemon overhead | 500 MB-1 GB | On macOS this is `com.docker.hyperkit` / VZ |
| **Total steady** | **~5-7 GB** | Consistent with PROJECT.md's 8-10 GB ceiling under load |

**Rules of thumb:**
- Do not run Jenkins builds and attack simulations concurrently.
- Keep only one demo-app replica in `deploy/overlays/local/`.
- `docker system prune` between demo rehearsals; old scan-blocked images accumulate.

---

## 11. Sources

Web verification was unavailable in this session; recommendations are based on established documented patterns for the specific fixed toolchain:

- k3d local registry pattern — `https://k3d.io/stable/usage/registries/` (from training data, MEDIUM confidence, verify before implementation)
- ArgoCD sub-path Application source — ArgoCD docs, `Application.spec.source.path` field (HIGH confidence)
- Falco modern_ebpf driver on Rancher Desktop — Falco 0.36+ release notes, aligned with PROJECT.md's own decision (HIGH confidence)
- Falcosidekick outputs matrix — Falcosidekick README (HIGH confidence, but exact YAML keys should be verified against installed chart version)
- JCasC + Trivy shell-step pattern — Jenkins JCasC docs + PROJECT.md key decisions (HIGH confidence)
- Kustomize overlay-per-env pattern — kustomize.io tutorials (HIGH confidence)

**Recommended verification during Phase 1 (bootstrap):**
- Exact `registries.yaml` syntax for the chosen cluster distribution (k3d vs Rancher Desktop).
- Current Falcosidekick chart values keys (they occasionally rename fields between minor versions).
- Whether `k3d-registry.localhost` hostname resolution works out-of-the-box on Apple Silicon macOS with the installed k3d version.
