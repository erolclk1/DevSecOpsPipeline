---
id: "01-01"
title: "Rancher Desktop + Registry Setup"
wave: 1
depends_on: []
requirements_addressed: [INFRA-01, INFRA-02]
files_modified:
  - cluster/registries.yaml
autonomous: true
must_haves:
  truths:
    - "kubectl get nodes returns a single node in Ready state"
    - "curl http://host.rancher-desktop.internal:5000/v2/ from the host returns {}"
    - "cluster/registries.yaml exists in the repo with the exact working mirror syntax"
  artifacts:
    - path: "cluster/registries.yaml"
      provides: "Containerd mirror config that tells k3s where to pull images"
      contains: "host.rancher-desktop.internal:5000"
  key_links:
    - from: "~/.rd/k3s/registries.yaml"
      to: "host.rancher-desktop.internal:5000"
      via: "Rancher Desktop containerd config reload on restart"
      pattern: "insecure_skip_verify: true"
---

<objective>
Stand up Rancher Desktop 1.23.1 as the sole local cluster, start a `registry:2` container on the host at port 5000, author the `registries.yaml` mirror config so k3s containerd can pull from `host.rancher-desktop.internal:5000` over HTTP, and verify both the cluster and host-side registry endpoints are healthy.

Purpose: Every subsequent phase pushes images to this registry and pulls from the cluster. Name-resolution correctness must be proven now — discovering it is broken during Phase 2 or later wastes multiple hours.

Output: Running k3s node (Ready), running registry container, `~/.rd/k3s/registries.yaml` committed to `cluster/registries.yaml` in the repo.
</objective>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@CLAUDE.md
</context>

<tasks>

<task id="1" title="Install Rancher Desktop 1.23.1 and verify the cluster node is Ready">
<read_first>
- CLAUDE.md — Critical Rules section (Docker socket path, registry hostname, no Docker Desktop conflict)
- .planning/research/PITFALLS.md — Pitfall 13 (Docker Desktop conflict on macOS)
</read_first>
<action>
1. Confirm Docker Desktop is NOT running. If it is installed, either uninstall it or run:
   ```
   docker context use rancher-desktop
   ```
   Verify with: `kubectl config current-context` — must return `rancher-desktop`.

2. Download and install Rancher Desktop 1.23.1 from https://github.com/rancher-sandbox/rancher-desktop/releases/tag/v1.23.1
   Select the macOS Apple Silicon (.aarch64.dmg) or Intel (.x86_64.dmg) installer as appropriate.

3. In Rancher Desktop Preferences:
   - Container engine: dockerd (moby)
   - Kubernetes: enabled, version pinned (accept the bundled k3s — do not change)
   - Resources → Memory: set to 6144 MB (6 GB). Do NOT leave at default 4 GB (insufficient for Phase 4+) and do NOT set above 6 GB (leaves too little for the host).
   - Allow the first-start provisioning to finish completely (watch the status bar in the Rancher Desktop UI).

4. Once the UI shows "Kubernetes: Running", open a terminal and run:
   ```
   kubectl version
   ```
   Record the exact k3s server version string (e.g. `v1.32.x+k3s1`). This resolves Open Question 3 from STATE.md — write it down for the SUMMARY step.

5. The Docker socket on Rancher Desktop is at `~/.rd/docker.sock`, NOT `/var/run/docker.sock`. Verify Docker is reachable:
   ```
   docker --context rancher-desktop version
   ```
   Or set the environment variable for the session: `export DOCKER_HOST=unix://$HOME/.rd/docker.sock`
</action>
<acceptance_criteria>
- `kubectl get nodes` output contains exactly one row and that row has STATUS `Ready`
- `kubectl config current-context` prints `rancher-desktop`
- `docker --context rancher-desktop version` exits 0 and shows Server Engine version
- Rancher Desktop UI shows "Kubernetes: Running" (not "Starting" or error state)
- k3s server version string has been recorded (e.g. `v1.32.x+k3s1`)
</acceptance_criteria>
</task>

<task id="2" title="Start registry:2 on host port 5000 and author registries.yaml">
<read_first>
- CLAUDE.md — Critical Rules: registry hostname must be `host.rancher-desktop.internal:5000`, never localhost, never a hardcoded IP
- .planning/research/PITFALLS.md — Pitfall 2 (registry cross-network problem)
- .planning/research/SUMMARY.md — Registry topology section
</read_first>
<action>
1. Start the registry container on the host:
   ```
   docker run -d --restart=always -p 5000:5000 --name registry registry:2
   ```
   If a container named `registry` already exists from a previous attempt: `docker rm -f registry` first, then re-run.

2. Verify the registry is up from the host:
   ```
   curl http://host.rancher-desktop.internal:5000/v2/
   ```
   Expected response: `{}`
   If `host.rancher-desktop.internal` does not resolve on the host, also try `curl http://localhost:5000/v2/` — the host-side push path uses `localhost` in Rancher Desktop's DNS; the CLUSTER-SIDE pull path must use `host.rancher-desktop.internal`. Do not conflate the two.

3. Create the Rancher Desktop containerd registry mirror config. The file path is:
   ```
   ~/.rd/k3s/registries.yaml
   ```
   Create the directory if it does not exist: `mkdir -p ~/.rd/k3s/`

   Write the following content exactly (this is the canonical content — do not paraphrase):
   ```yaml
   mirrors:
     "host.rancher-desktop.internal:5000":
       endpoint:
         - "http://host.rancher-desktop.internal:5000"
   configs:
     "host.rancher-desktop.internal:5000":
       tls:
         insecure_skip_verify: true
   ```

4. Restart Rancher Desktop to reload the containerd config. Either:
   - Use the Rancher Desktop menu → Restart, or
   - Run: `rdctl shutdown && rdctl start`
   Wait for "Kubernetes: Running" to return in the UI before proceeding.

5. Verify that the registry is still running after the restart (the `--restart=always` flag should bring it back automatically):
   ```
   docker ps | grep registry
   curl http://host.rancher-desktop.internal:5000/v2/
   ```

6. Copy the working `registries.yaml` into the repo as the Phase 1 artefact:
   ```
   mkdir -p cluster/
   cp ~/.rd/k3s/registries.yaml cluster/registries.yaml
   ```
   Add it to git: `git add cluster/registries.yaml`

   Note: `cluster/registries.yaml` is the repo artefact (thesis evidence). `~/.rd/k3s/registries.yaml` is the live system config. They must have identical content.
</action>
<acceptance_criteria>
- `docker ps | grep registry` shows a container named `registry` with status `Up` and port `0.0.0.0:5000->5000/tcp`
- `curl http://host.rancher-desktop.internal:5000/v2/` returns `{}` with HTTP 200
- File `~/.rd/k3s/registries.yaml` exists and contains `insecure_skip_verify: true` and `host.rancher-desktop.internal:5000`
- File `cluster/registries.yaml` exists in the repo with identical content to `~/.rd/k3s/registries.yaml`
- `kubectl get nodes` still shows one Ready node after the Rancher Desktop restart
</acceptance_criteria>
</task>

</tasks>

## Verification

**must_haves:**
- `kubectl get nodes` shows exactly one node in `Ready` state — cluster is up
- `curl http://host.rancher-desktop.internal:5000/v2/` from host returns `{}` — registry is reachable from host with the correct hostname
- `~/.rd/k3s/registries.yaml` contains the exact mirror and tls config above — containerd will use it on next image pull
- `cluster/registries.yaml` is committed to the repo — Phase 1 artefact exists
- k3s server version has been noted (resolves Open Question 3 in STATE.md)
