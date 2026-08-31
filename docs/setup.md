# Setup Guide — DevSecOps Pipeline Thesis

Step-by-step bootstrap for a fresh **Windows 10/11 with WSL2** machine.

> Target machine: Windows + WSL2 + Rancher Desktop 1.23.1.  
> Dev machine (code authoring only): macOS. Do not run these steps on macOS.

---

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| Rancher Desktop | 1.23.1 | Download from https://github.com/rancher-sandbox/rancher-desktop/releases/tag/v1.23.1 |
| RAM | 16 GB recommended (12 GB minimum) | Set VM memory to 6 GB in RD → Preferences → Resources |
| Disk | 20 GB free | Trivy DB + images |
| Git | any | Clone the mono-repo |
| Python 3 | 3.10+ | For `attacks/sqli.py` |

> Do NOT install Docker Desktop alongside Rancher Desktop. They conflict for the `docker` CLI and `kubectl` context.

---

## Step 1: Install and Configure Rancher Desktop

1. Install Rancher Desktop 1.23.1.
2. Open Preferences → Resources → set Memory to **6 GB**.
3. Under Container Engine, choose **dockerd (moby)** (not containerd).
4. Wait for the tray icon to show **Kubernetes: Running**.

---

## Step 2: Clone the Repository

```bash
git clone <repo-url>
cd myProject
```

---

## Step 3: Bootstrap Phase 1 (Registry + Registry Config)

```bash
make up
```

This target:
1. Starts `registry:2` on host port **5001** (`localhost:5001`).
2. Copies `cluster/registries.yaml` → `~/.rd/k3s/registries.yaml` (k3s mirror config).
3. Prints a **STOP** message — you must restart Rancher Desktop before continuing.

> **Why port 5001?** Rancher Desktop binds port 5000 internally. Port 5001 avoids the conflict.

---

## Step 4: Configure insecure-registries in the VM

The `dockerd` engine inside the Rancher Desktop VM **ignores `registries.yaml`** for its own pulls. You must add an `insecure-registries` entry to `/etc/docker/daemon.json` inside the VM.

This is handled automatically by the `cluster/insecure-registry.start` provisioning script, which Rancher Desktop runs on startup. Verify it is in place:

```bash
wsl -d rancher-desktop -- cat /etc/docker/daemon.json
```

Expected output contains:
```json
{
  "insecure-registries": ["host.rancher-desktop.internal:5001"]
}
```

If the file is missing or empty, copy the provisioning script:
```bash
# (Run once — RD applies provisioning scripts on next start)
wsl -d rancher-desktop -- sudo cp /mnt/host/path/to/cluster/insecure-registry.start \
    /etc/rancher-desktop/provisioning/insecure-registry.start
```

---

## Step 5: Restart Rancher Desktop

```bash
rdctl shutdown && rdctl start
```

Wait ~60 seconds for the tray icon to show **Kubernetes: Running** again.

---

## Step 6: Verify Phase 1

```bash
make verify-phase-1
```

Expected: `curl http://localhost:5001/v2/` returns `{}` and a smoke pod reaches Running.

---

## Step 7: Build and Push the Demo App (Phase 2)

```bash
make phase-2        # docker build + Trivy scan + push to localhost:5001/demoapp:<sha>
make phase-2-deploy # kubectl apply kustomize overlay + rollout
make verify-phase-2 # confirm pod Running + endpoints exploitable
```

---

## Step 8: Bootstrap Full Stack (ArgoCD + Kyverno + Jenkins + Falco)

```bash
make stack
```

This chains: ArgoCD install → ArgoCD Application CR → Kyverno + 4 policies → Jenkins (JCasC) → Falco (modern_ebpf).

Expected duration: 8–12 minutes. All components print `✓` on success.

---

## Step 9: Verify Full Stack

```bash
make status
```

All five sections (Cluster, Registry, ArgoCD, Falco, Jenkins) should show running/healthy state.

---

## Step 10: Pre-Warm Before Demo

Run this **before the committee arrives**:

```bash
make demo-warmup
```

This pre-downloads the Trivy vulnerability DB so `demo-1` does not stall on first run.

---

## Troubleshooting

### 1. Registry unreachable from inside the cluster (ImagePullBackOff)

**Symptom:** `kubectl describe pod` shows `Failed to pull image "host.rancher-desktop.internal:5001/demoapp:..."`

**Fix:** Verify `/etc/docker/daemon.json` inside the VM has `insecure-registries` (Step 4). Then restart Rancher Desktop.

### 2. Falco CrashLoopBackOff

**Symptom:** `kubectl get pods -n falco` shows `CrashLoopBackOff`

**Fix:** Verify BTF file exists:
```bash
wsl -d rancher-desktop -- ls /sys/kernel/btf/vmlinux
```
If missing, the kernel is too old for `modern_ebpf`. Rancher Desktop 1.23.1 bundles a kernel that supports BTF — ensure you are on the correct version.

### 3. Jenkins API returns 403 (CSRF)

**Symptom:** `curl -X POST http://localhost:8080/...` returns HTTP 403

**Fix:** Jenkins requires a crumb for POST requests. Use a cookie jar:
```bash
CRUMB=$(curl -s --cookie-jar /tmp/cookies \
    http://admin:admin@localhost:8080/crumbIssuer/api/json)
FIELD=$(echo "$CRUMB" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['crumbRequestField'])")
VALUE=$(echo "$CRUMB" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['crumb'])")
curl -X POST --cookie /tmp/cookies -H "$FIELD: $VALUE" http://admin:admin@localhost:8080/...
```

### 4. Docker socket path

On Windows/WSL2 with Rancher Desktop dockerd engine, the Docker socket is:
- **Correct:** `/var/run/docker.sock`
- **Wrong:** `~/.rd/docker.sock` (that path is macOS/lima only)

The Jenkins agent `docker-compose.yml` mounts `/var/run/docker.sock` — this is intentional and correct for Windows/WSL2.

---

## Resource Budget

| Component | RAM (approximate) |
|-----------|------------------|
| k3s (Rancher Desktop VM) | 1.5 GB |
| ArgoCD (non-HA) | 0.5 GB |
| Jenkins controller + agent | 1.5 GB |
| Falco + Falcosidekick | 0.5 GB |
| Demo app pod | 0.1 GB |
| **Total** | **~4.1 GB** (6 GB VM allocation recommended) |

> During a Jenkins build (`demo-2`), add ~1 GB for the Trivy scan. Peak RAM approaches 5 GB inside the VM.
> **Never run `demo-2` and `demo-3` concurrently.** Demos are strictly sequential.
