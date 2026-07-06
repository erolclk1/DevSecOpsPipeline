# Technology Stack — DevSecOps Pipeline Thesis

**Project:** DevSecOps CI/CD Pipeline (locally runnable)
**Researched:** 2026-07-02
**Overall confidence:** HIGH (all versions verified against official GitHub releases / changelogs)

Tools are **fixed by thesis assignment** — this document pins current versions, integration points, and configuration rationale. It does not propose replacements.

---

## Recommended Stack (Pinned Versions)

### Core CI/CD

| Technology | Version | Purpose | Why this version | Confidence |
|------------|---------|---------|------------------|------------|
| Jenkins LTS | **2.555.3** (2026-06-10) | CI orchestration | Latest LTS; contains fix preventing active builds being lost on job reload — relevant since the pipeline runs one long build+scan job. Requires **Java 21 or 25** (mandatory since 2.555.1). | HIGH |
| ArgoCD | **v3.4.4** (2026-06-18) | GitOps CD | Latest stable on v3.4 line; images cosign-signed; RBAC and health-check fixes over v3.3. v3.5.0-rc2 exists but is a release candidate — avoid for thesis reproducibility. | HIGH |
| argo-cd Helm chart | **10.1.0** (2026-07-01) | ArgoCD install method | Newest chart on `argoproj/argo-helm`, tracks ArgoCD v3.4.x. Chart-based install keeps the setup declarative and reproducible for the thesis demo. | HIGH |

### Container Runtime & Cluster

| Technology | Version | Purpose | Why this version | Confidence |
|------------|---------|---------|------------------|------------|
| Rancher Desktop | **1.23.1** (2026-06-29) | Docker + k3s. Target machine: **Windows** (WSL2 backend). Dev machine: macOS (code authoring only). | HIGH |
| k3s (bundled) | v1.32.x (via Rancher Desktop 1.23.1) | Kubernetes cluster | Single-node k3s from Rancher Desktop meets thesis "locally runnable" constraint. No hypervisor tuning required. | MEDIUM (specific k3s minor version depends on Rancher Desktop image; verify with `kubectl version` post-install) |
| Docker Engine | 27.x (via Rancher Desktop) | Container build/runtime | Bundled by Rancher Desktop; buildx available for multi-arch (Apple Silicon → linux/amd64 if needed). | HIGH |

### Security Tooling

| Technology | Version | Purpose | Why this version | Confidence |
|------------|---------|---------|------------------|------------|
| Trivy | **v0.72.0** (2026-06-30) | Container vulnerability scan | Latest release; use CLI (not Jenkins plugin) per PROJECT.md decision — output identical, debugging easier. Static binary, no daemon. | HIGH |
| Falco | **0.44.1** (2026-06-11) | Runtime security | Latest stable; **v0.44.0 deprecated the legacy BPF probe, gVisor, and gRPC output** — must use `modern_ebpf` on Rancher Desktop (kmod path already blocked by missing kernel headers in the VM). | HIGH |
| Falco Helm chart | **9.1.0** | Falco install method | Current chart on `falcosecurity/charts`. Default `driver.kind: auto` picks modern_ebpf first — we pin it explicitly to avoid silent fallback. | HIGH |

### Demo Application

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Node.js | **22 LTS (Jod)** | REST API runtime | Active LTS through 2027; Alpine base gives ~50 MB image; well-understood attack surface for SQLi demo. | HIGH |
| Alternative: Python | **3.12** | REST API runtime | Also acceptable per thesis; Flask/FastAPI gives smaller learning curve if student prefers Python. Slightly larger image (~80–120 MB Alpine). | HIGH |
| Base image | `node:22-alpine` or `python:3.12-alpine` | Slim distro | Alpine intentionally used to keep Trivy scan results readable (fewer transitive CVEs than Debian slim). | HIGH |

### Local Registry

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| `registry:2` (Docker distribution) | **2.8.3+** | Local image store | Plain OCI registry container, bound to `localhost:5000`. Required because Jenkins pushes from host and k3s must pull inside VM — see registry section below. | HIGH |
| k3d built-in registry | k3d v5.9.0 (last release 2024-06-02) | Alternative registry | k3d has had no release since 2024 — MEDIUM staleness risk. Keep in mind if student swaps Rancher Desktop for k3d. | MEDIUM |

---

## Jenkins Plugins (Required Set)

Install via JCasC `plugins.txt` to keep the config reproducible.

| Plugin | Purpose | Why required |
|--------|---------|--------------|
| `configuration-as-code` | JCasC | Whole-Jenkins config from YAML — mandatory per PROJECT.md key decision |
| `workflow-aggregator` | Pipeline (declarative + scripted) | Base pipeline engine |
| `pipeline-stage-view` | Pipeline UI | Visual demo of stages passing/blocking — thesis screenshots |
| `docker-workflow` (Docker Pipeline) | `docker.build`, `docker.image` DSL | Build vulnerable image inside Jenkinsfile |
| `docker-plugin` | Docker cloud (optional) | Not needed if using shell + `docker build`; include only if using dynamic agents |
| `credentials` + `credentials-binding` | Secret management | Registry creds, Git tokens injected via `withCredentials {}` |
| `git` + `git-client` | Git SCM | Clone demo repo + manifests repo |
| `github` (optional) | GitHub webhook trigger | For when student adds remote repo |
| `job-dsl` | Seed job for JCasC | Bootstraps the pipeline job from config |
| `timestamper` | Log timestamps | Correlating scan output with Falco events in demo |
| `ansicolor` | Colored console | Trivy severity output stays readable |
| `matrix-auth` | RBAC | JCasC-friendly authorization strategy |

**Explicitly NOT installed:**
- Trivy Jenkins plugin — per PROJECT.md decision, use shell step. Plugin wraps the same binary, adds indirection, and is harder to debug.
- Blue Ocean — heavy, opinionated UI; classic pipeline view is sufficient and lighter on the 16 GB laptop budget.

**Confidence:** HIGH (all plugins are actively maintained on plugins.jenkins.io and part of the standard JCasC recipe).

### Jenkins Docker socket binding

Run Jenkins container with:
```
-v /var/run/docker.sock:/var/run/docker.sock
--group-add <docker gid inside container>
```
Grants the `jenkins` user in-container access to the host Docker daemon so `docker build`/`docker push` work without DinD. On Rancher Desktop, socket path is `~/.rd/docker.sock` — bind that instead.

**Confidence:** HIGH.

---

## Trivy CLI Flags for Jenkins Integration

Recommended invocation for the "block on high CVE" stage:

```bash
trivy image \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --exit-code 1 \
  --scanners vuln \
  --format table \
  --no-progress \
  --cache-dir /var/jenkins_home/.trivy-cache \
  "$IMAGE:$TAG"
```

| Flag | Rationale |
|------|-----------|
| `--severity HIGH,CRITICAL` | Thesis demo needs a clear block/pass line. LOW/MEDIUM would cause noisy failures on Alpine images. |
| `--ignore-unfixed` | Only fail on CVEs the developer can actually remediate (patched upstream). Prevents "unfixable Alpine libssl" false-block. |
| `--exit-code 1` | Non-zero exit fails the Jenkins stage — this is the "block" mechanism. `--exit-code 0` (default) would only log. |
| `--scanners vuln` | Restrict to vulnerability scanner; skip secret/misconfig scanners for the CI stage (run those separately if desired). |
| `--format table` | Human-readable in Jenkins console. Add a second Trivy call with `--format sarif -o trivy.sarif` if archiving reports. |
| `--no-progress` | Cleaner Jenkins logs — no TTY progress bars. |
| `--cache-dir` inside `$JENKINS_HOME` | Persists the vulnerability DB across builds; avoids ~200 MB re-download every run. |

**Second parallel invocation for reporting (does NOT fail build):**
```bash
trivy image --severity LOW,MEDIUM --format json -o trivy-informational.json "$IMAGE:$TAG" || true
```

**Confidence:** HIGH (flags verified in Trivy v0.72.0 CLI reference; pattern is the canonical CI recipe in Aqua's own tutorials).

---

## Falco: modern_ebpf Configuration

### Why modern_ebpf on Rancher Desktop

Rancher Desktop's VM (based on Alpine + lima) does **not** ship kernel headers, so:
- `driver.kind: kmod` → falco tries to compile the kernel module → fails, DaemonSet CrashLoopBackOff
- `driver.kind: ebpf` (legacy) → **deprecated in Falco 0.44.0**, removed in 0.45+ per changelog
- `driver.kind: modern_ebpf` → uses CO-RE eBPF probe **shipped inside the Falco binary itself**, requires only a modern-enough kernel

### Kernel requirement

modern_ebpf needs Linux **5.8+** with BTF (BPF Type Format) enabled. Rancher Desktop 1.23.1 ships a 6.x kernel — requirement satisfied. Verify with:
```bash
kubectl debug node/<node> -it --image=busybox -- uname -r
ls /sys/kernel/btf/vmlinux   # must exist
```

### Helm install command

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
helm install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --version 9.1.0 \
  --set driver.kind=modern_ebpf \
  --set tty=true \
  --set falcosidekick.enabled=true \
  --set falcosidekick.webui.enabled=true \
  --set collectors.kubernetes.enabled=true
```

| Value | Rationale |
|-------|-----------|
| `driver.kind=modern_ebpf` | Explicit — do not rely on `auto` (silent fallback hides misconfig) |
| `tty=true` | Flushes stdout immediately so `kubectl logs -f` shows detections live in the demo |
| `falcosidekick.enabled + webui` | Gives a browser UI for the thesis demonstration — much better screenshots than tailing logs |
| `collectors.kubernetes.enabled` | Enriches events with pod/namespace metadata; essential for correlating an attack to the demo app |

**Confidence:** HIGH.

### Custom rules

Store custom rules in a ConfigMap and mount at `/etc/falco/rules.d/custom.yaml`. Thesis-relevant rule stubs:
- `Reverse Shell Spawned` (already in falcosecurity/rules — enable, don't rewrite)
- `Suspicious Network Tool Executed in Container` (nc, socat, nmap)
- `Shell in Container` (bash/sh spawned as child of node/python)

---

## Local Docker Registry — Decision Matrix

Thesis requires: **image reachable from Jenkins on host AND from k3s inside Rancher Desktop VM.**

### Option A: `registry:2` container on host (RECOMMENDED)

```bash
docker run -d --restart=always -p 5000:5000 --name registry registry:2
```

Configure Rancher Desktop to trust `host.docker.internal:5000` (or `192.168.5.2:5000` — the VM's gateway IP for host) as an insecure registry, via `~/.rd/k3s/registries.yaml`:

```yaml
mirrors:
  "host.docker.internal:5000":
    endpoint:
      - "http://host.docker.internal:5000"
configs:
  "host.docker.internal:5000":
    tls:
      insecure_skip_verify: true
```

**`registries.yaml` path by OS:**
| OS | Path |
|----|------|
| macOS | `~/.rd/k3s/registries.yaml` |
| Windows (Git Bash / WSL2) | `~/.rd/k3s/registries.yaml` (WSL2 home maps to the same RD data dir) |
| Windows (native) | `%APPDATA%\rancher-desktop\lima\data\k3s\registries.yaml` |

On Windows, after editing the file, restart RD: `rdctl shutdown && rdctl start` (works from PowerShell, CMD, or Git Bash).

**Pros:** Simple, well-documented, works with any orchestrator. Independent of Rancher Desktop lifecycle.
**Cons:** Need to configure k3s to trust it (one-time file edit).

### Option B: k3d built-in registry

Only applicable if student swaps Rancher Desktop → k3d. `k3d cluster create --registry-create` auto-wires DNS between cluster and registry. But k3d has no release since **v5.9.0 (June 2024)** — 2-year staleness. Not recommended for a thesis due in 2026.

### Recommendation

Use **Option A (`registry:2`)** with Rancher Desktop. It matches PROJECT.md's Rancher Desktop decision, avoids the k3d staleness risk, and is the canonical setup in every DevSecOps tutorial.

**Confidence:** HIGH.

---

## k3d vs Rancher Desktop — Local Cluster Tradeoffs

| Criterion | Rancher Desktop 1.23.1 | k3d v5.9.0 |
|-----------|------------------------|------------|
| Release recency | 2026-06 (current) | 2024-06 (stale) |
| Bundled Docker | Yes (single install) | No — needs Docker Desktop or colima |
| Registry integration | Manual `registries.yaml` edit | Auto-wired via `--registry-create` |
| macOS Apple Silicon | Native | Needs Docker Desktop / Rancher Desktop underneath anyway |
| GUI | Yes (helpful for thesis demo) | No (CLI only) |
| RAM baseline | ~1.5 GB | ~600 MB (excl. Docker daemon) |
| Multi-node testing | Single-node only | Trivial multi-node |

**Verdict:** Rancher Desktop wins for this thesis — matches PROJECT.md, single install, current, single-node is all we need. k3d's advantages (multi-node, faster spin-up) are irrelevant here.

**Confidence:** HIGH.

---

## Installation Order (for roadmap Phase 1)

**All commands run on the target Windows machine.** Dev machine (macOS) only edits code.

**Windows (Git Bash / PowerShell):**
```bash
# 1. Install Rancher Desktop 1.23.1 from the Windows installer (.exe)
#    After install, set Container Engine = dockerd, Memory = 6144 MB

# Docker socket on Windows:
#   Git Bash: set DOCKER_HOST=npipe:////./pipe/docker_engine
#   WSL2:     /var/run/docker.sock  (RD bridges it automatically)
#   PowerShell/CMD: uses Windows named pipe natively after RD installs docker CLI

# 2. Local registry (Git Bash or PowerShell)
docker run -d --restart=always -p 5000:5000 --name registry registry:2

# 3. Configure registries.yaml on Windows
#    Option A — Git Bash (path inside WSL2-mapped home):
mkdir -p ~/.rd/k3s/
# write registries.yaml to ~/.rd/k3s/registries.yaml

#    Option B — Windows native path (PowerShell):
#    $env:APPDATA\rancher-desktop\lima\data\k3s\registries.yaml

# Restart RD after editing:
rdctl shutdown && rdctl start

# 4. Jenkins (Git Bash) — Docker socket path differs on Windows
docker run -d --name jenkins \
  -p 8080:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v //./pipe/docker_engine://./pipe/docker_engine \
  -e CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml \
  jenkins/jenkins:2.555.3-lts-jdk21
# Note: on Windows the socket binding uses Windows named pipe syntax.
# Alternative: run Jenkins in WSL2 and bind /var/run/docker.sock instead.

# 5. ArgoCD — same as macOS; kubectl works from PowerShell/Git Bash post-RD install
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd --version 10.1.0 \
  --namespace argocd --create-namespace

# 6. Falco — same helm command; modern_ebpf works on WSL2 kernel
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm install falco falcosecurity/falco --version 9.1.0 \
  --namespace falco --create-namespace \
  --set driver.kind=modern_ebpf --set tty=true
```

**macOS reference (dev machine — do NOT run the pipeline here):**
```bash
# 1. Host tools (code authoring / CLI only)
brew install --cask rancher-desktop     # only if you want a local test env
brew install helm kubectl trivy         # trivy 0.72.0

# 2-6: same as Windows above, with macOS paths
#   registries.yaml: ~/.rd/k3s/registries.yaml
#   Jenkins Docker socket: -v ~/.rd/docker.sock:/var/run/docker.sock
```

---

## Alternatives Considered (and rejected — thesis constraint)

| Category | Locked-in (thesis) | Alternative | Why not (context) |
|----------|-------------------|-------------|-------------------|
| CI | Jenkins | GitHub Actions | Thesis requires locally runnable + self-hosted; GH Actions cloud is out of scope |
| CD | ArgoCD | Flux CD | ArgoCD's UI is more demonstrable for a thesis defense; both are GitOps-native |
| Cluster | k3s (Rancher Desktop) | Minikube, kind | RAM baseline 2–4× higher; Minikube has hypervisor quirks on macOS |
| Scanner | Trivy | Snyk, Mend | Trivy is FOSS, sufficient — Out of Scope per PROJECT.md |
| Runtime security | Falco | Tetragon, Tracee | Falco is CNCF graduated, standard reference in academic DevSecOps literature |

---

## Sources

- Jenkins LTS changelog — https://www.jenkins.io/changelog-stable/
- ArgoCD releases — https://github.com/argoproj/argo-cd/releases
- argo-helm releases — https://github.com/argoproj/argo-helm/releases
- Trivy releases — https://github.com/aquasecurity/trivy/releases
- Trivy container image docs — https://trivy.dev/latest/docs/target/container_image/
- Falco releases — https://github.com/falcosecurity/falco/releases
- Falco Helm chart — https://github.com/falcosecurity/charts/tree/master/charts/falco
- Falco chart on Artifact Hub — https://artifacthub.io/packages/helm/falcosecurity/falco
- ArgoCD chart on Artifact Hub — https://artifacthub.io/packages/helm/argo/argo-cd
- Rancher Desktop releases — https://github.com/rancher-sandbox/rancher-desktop/releases
- k3d releases — https://github.com/k3d-io/k3d/releases
- Jenkins plugin index — https://plugins.jenkins.io/

---

## Confidence Summary

| Area | Confidence | Reason |
|------|------------|--------|
| Jenkins version + plugins | HIGH | Official changelog, current LTS |
| ArgoCD + Helm chart | HIGH | Official GitHub releases verified |
| Trivy version + flags | HIGH | Official releases + docs cross-checked |
| Falco version + modern_ebpf | HIGH | Official releases + chart docs verified |
| Rancher Desktop | HIGH | Official releases verified |
| k3s bundled version | MEDIUM | Depends on RD image build; verify post-install |
| k3d as alternative | MEDIUM | No release since 2024-06, staleness flag |
| Registry approach | HIGH | Canonical pattern, matches PROJECT.md constraints |
