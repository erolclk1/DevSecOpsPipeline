# Domain Pitfalls — Locally-Runnable DevSecOps Pipeline

**Domain:** Local DevSecOps CI/CD (Jenkins + Trivy + ArgoCD + k3s + Falco) on macOS/Linux
**Researched:** 2026-07-02
**Overall confidence:** HIGH on the 5 pre-identified risks (well-documented community pain), MEDIUM on Falco/ArgoCD/Trivy detail (training-data-supported, not re-verified against current docs today because WebSearch/Fetch were unavailable this session)

> **Confidence note:** WebSearch returned an environment error (`tool type 'web_search_20250305' is not supported`) and WebFetch on canonical URLs did not surface troubleshooting content. Findings below rely on training-data knowledge of these tools plus the project's own stated context. Where a claim is single-source or unverified against 2026 docs, it is flagged **LOW** and should be validated before acting on it in a phase.

---

## Critical Pitfalls (Confirmed / Expanded from Known Risks)

### Pitfall 1: Jenkins Docker socket binding — controller vs. agent confusion
**Warning signs (early):**
- `docker: command not found` inside pipeline `sh` step
- `permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock`
- Trivy runs but reports `unable to inspect the image` or `no such image` after a successful `docker build`
- The controller image itself grows to multi-GB because builds land inside `/var/jenkins_home`

**What goes wrong:**
Newcomers bind-mount `/var/run/docker.sock` into the **Jenkins controller** container so that the pipeline can call `docker build`. This mixes controller state (jobs, secrets, users) with build workload. Two failure modes result:
1. **Security blast radius:** any pipeline `sh` step can now `docker run --privileged` on the host, escape, and mount the host filesystem. This makes the Docker socket effectively equivalent to root on the host.
2. **Wrong container:** users mount the socket into the controller but run builds on an ephemeral agent that does *not* have the socket — resulting in `docker: not found` mid-build.

**Prevention strategy:**
- Run a dedicated **agent container** (e.g. `jenkins/inbound-agent` + `docker:cli`) with the socket mounted **only there**, not on the controller.
- In `docker-compose.yml`, keep the controller's volumes limited to `jenkins_home`; add a separate `jenkins-agent` service with `/var/run/docker.sock:/var/run/docker.sock` and label it (e.g. `docker-builder`).
- Pin pipeline stages that need Docker with `agent { label 'docker-builder' }`; leave lightweight stages on the built-in node.
- Scope Docker Hub / registry credentials to the agent job, not global Jenkins credentials, via JCasC `folder-scoped` or `job-scoped` credentials.
- Long term: prefer `buildah`/`kaniko`/`img` (rootless, no socket) — but for a thesis demo, socket-on-agent is the pragmatic choice.

**Detection commands:**
```bash
docker inspect jenkins-controller | jq '.[0].Mounts'   # should NOT contain docker.sock
docker inspect jenkins-agent      | jq '.[0].Mounts'   # SHOULD contain docker.sock
```

**Phase to address:** Phase where Jenkins is stood up (first CI phase). Cheapest to fix before any pipeline is authored.
**Confidence:** HIGH

---

### Pitfall 2: Local registry cross-network problem — `localhost:5000` is not the same address in two places
**Warning signs (early):**
- `docker push localhost:5000/demo:tag` succeeds from the host
- `kubectl describe pod` shows `Failed to pull image "localhost:5000/demo:tag": ... connection refused` or `no such host`
- Manifests reference the registry with an IP address that becomes stale on the next `rancher-desktop` restart

**What goes wrong:**
Rancher Desktop runs k3s inside a **Lima VM** (macOS) or a lightweight VM/namespace (Linux). Inside the VM, `localhost` = the VM itself, not the host machine. The registry running on the host at `127.0.0.1:5000` is unreachable from any pod. Worse, k3s's containerd doesn't consult `/etc/hosts` on the host; it uses its own `registries.yaml`.

**Prevention strategy (in order of robustness):**
1. **Preferred: `k3d`-managed local registry** — `k3d registry create` creates a container the k3d cluster is pre-wired to trust; both host and cluster resolve `k3d-registry.localhost:5000`. This is exactly why the project's Key Decisions row picks k3d.
2. **If sticking with Rancher Desktop:** create `/etc/rancher/k3s/registries.yaml` inside the VM with:
   ```yaml
   mirrors:
     "host.rancher-desktop.internal:5000":
       endpoint: ["http://host.rancher-desktop.internal:5000"]
   configs:
     "host.rancher-desktop.internal:5000":
       tls:
         insecure_skip_verify: true
   ```
   Then push and reference images as `host.rancher-desktop.internal:5000/demo:tag`. Restart k3s (`rdctl shutdown && rdctl start`) after edits — the file is loaded only on containerd startup.
3. Do **not** hardcode the host's LAN IP in manifests — it changes on Wi-Fi/DHCP roams and breaks the demo.
4. Add `insecure-registries` to Docker Desktop / Rancher Desktop preferences so pushes over HTTP don't require certificate provisioning.

**Detection commands:**
```bash
kubectl run curl --rm -it --image=curlimages/curl -- sh -c \
  'curl -v http://k3d-registry.localhost:5000/v2/_catalog'
```

**Phase to address:** Phase that introduces the registry (before first Jenkins push). Wasting a day here is the #1 momentum killer in reports of this stack.
**Confidence:** HIGH

---

### Pitfall 3: Falco probe loading on macOS — kmod fails, must use modern_ebpf
**Warning signs (early):**
- `falco: driver 'kmod' initialization failed` in pod logs
- `Unable to load kernel module: no such file or directory: /lib/modules/...`
- Falco pod stuck `CrashLoopBackOff` immediately after Helm install
- On Rancher Desktop: `dkms` errors even though the VM claims to have build tools

**What goes wrong:**
Rancher Desktop's Lima VM (and most desktop k3s distros) ship without kernel headers matching the running kernel, so the Falco kernel module (`kmod`) cannot compile or load. The default Helm chart still tries `kmod` first on some versions.

**Prevention strategy:**
- Install Falco with `driver.kind=modern_ebpf` (CO-RE eBPF, no headers required, kernel ≥ 5.8):
  ```bash
  helm install falco falcosecurity/falco \
    --namespace falco --create-namespace \
    --set driver.kind=modern_ebpf \
    --set falcosidekick.enabled=true
  ```
- Verify the kernel supports it: `uname -r` should be ≥ 5.8 (Rancher Desktop's Lima kernel is well above this in 2026).
- **Not** `driver.kind=ebpf` (legacy probe, still needs some build assets on some distros). Modern eBPF is the CO-RE path.
- If pod still fails: check `SYS_BPF` / `SYS_PERFMON` capabilities on the DaemonSet; some hardened distros drop them.

**Detection commands:**
```bash
kubectl -n falco logs -l app.kubernetes.io/name=falco --tail=50 | grep -i driver
# expect: "driver: modern_ebpf" and "Falco initialized"
```

**Phase to address:** Runtime-detection phase (after cluster + registry work).
**Confidence:** HIGH

---

### Pitfall 4: RAM budget blowout — 8–10 GB steady state on a 16 GB machine
**Warning signs (early):**
- macOS swap pressure > 4 GB (Activity Monitor)
- Rancher Desktop VM crashes with `oom-killer` in `dmesg`
- Jenkins agents timing out during `docker build` because kernel is thrashing
- Falco starts dropping events (`n_drops` metric climbing)

**What goes wrong:**
Baseline: Rancher Desktop (~3 GB) + k3s core (~0.7 GB) + ArgoCD (~1 GB, all controllers) + Jenkins controller (~0.7 GB) + Jenkins agent during build (~1–2 GB) + Trivy scan (~0.5–1 GB, spikes higher with large images) + Falco (~0.4 GB) + demo app (~0.2 GB) ≈ 8–10 GB before browser and IDE. A second concurrent build or an attack simulation puts it over 12 GB and macOS starts swapping, which slows every pod's healthcheck and cascades into `CrashLoopBackOff`.

**Prevention strategy:**
- Set explicit `resources.limits` on every deployment (Jenkins, ArgoCD, Falco, demo app). ArgoCD's default HA-style manifests are memory-hungry — install with the **non-HA** manifest or the Helm chart with `redis-ha.enabled=false`, `controller.replicas=1`, `server.replicas=1`.
- Configure Rancher Desktop VM to 6 GB (not the default 4, not the maximum 12). Leaves ~10 GB for host.
- Serialize workloads: never run a build *and* an attack simulation *and* a Falco stress test simultaneously. Document this in the demo runbook.
- Pin Trivy DB cache to a persistent volume so DB downloads don't recur inside memory-limited containers.
- Consider `argocd-cmd-params-cm` tuning: `controller.status.processors=1`, `controller.operation.processors=1` for local use.
- Disable Jenkins plugins you're not using (Blue Ocean is a memory hog; the classic UI is fine for a thesis demo).

**Detection commands:**
```bash
kubectl top pods -A --sort-by=memory
docker stats --no-stream
vm_stat | awk '/Pages free/ || /Swapouts/'
```

**Phase to address:** Every phase (running budget); explicitly reviewed at end of each infrastructure phase.
**Confidence:** HIGH

---

### Pitfall 5: Jenkins first green run takes 4–6 hours
**Warning signs (early):**
- Repeatedly logging into the UI to "just fix one thing" — indicates config is not codified
- `Jenkinsfile` grows monolithic; secrets pasted as inline strings
- No `casc.yaml` in Git; state lives only in `jenkins_home` volume
- Trivy invoked via the Jenkins plugin (opaque failures) rather than a shell step

**What goes wrong:**
Jenkins has ~30 knobs that all need to align: JCasC configuration, plugin versions, agent connection, credential IDs matching the Jenkinsfile, Docker socket permissions, and the pipeline itself. A single mismatch (e.g. credential ID typo, plugin depending on a plugin one version behind) blocks the entire pipeline. First-time users typically spend 4–6 hours on the first green run because failures are 15 minutes apart and each fix restarts the container.

**Prevention strategy:**
- **JCasC from day 1**, per the project's Key Decisions. Ship `casc.yaml` with credentials referenced by ID (loaded via `-e CREDS_XXX=...`), not hard-coded.
- Pin plugin versions in `plugins.txt` with `:version` (not `:latest`) — reproducible, avoids "worked yesterday" regressions.
- Trivy as a shell step, not the plugin — you can `docker run aquasec/trivy:<pinned>` and pipe SARIF into an artifact.
- Iterate the Jenkinsfile with `Replay` in the UI first, then commit — cuts feedback loop from 90 s (SCM poll) to 5 s.
- Use `--restart=no` for the Jenkins container while iterating so a bad JCasC change doesn't crashloop and mask logs.
- Structure pipeline in isolatable stages so `when { changeset }` skips work when iterating on a single stage.
- Keep a `jenkins-reset.sh` script that wipes `jenkins_home` and reprovisions from JCasC — required for reproducibility in a thesis.

**Detection commands:**
```bash
docker exec jenkins bash -c 'jenkins-plugin-cli --list' > current-plugins.txt
diff plugins.txt current-plugins.txt   # should be empty
```

**Phase to address:** First CI phase, invested up front to avoid compound pain later.
**Confidence:** HIGH

---

## Additional Pitfalls (Beyond the Known 5)

### Pitfall 6: Falco custom rules — false positives that make the demo un-demoable
**Warning signs:**
- Falco alerts fire during normal `kubectl exec` for debugging
- Any `apt-get`, `curl`, or shell in a container triggers "Terminal shell in container"
- Alert stream is so noisy that the actual attack signal is buried
- Rules built on `proc.name` alone (easily spoofed)

**What goes wrong:**
Default Falco rules are tuned for production. In a dev environment, kubectl exec, package installs during image builds, and health check probes all trip them. If custom rules use only `proc.name = "nc"` or `proc.name = "bash"`, any renamed binary evades detection while any legitimate use fires the alert.

**Prevention strategy:**
- **Layer conditions**: combine `proc.name`, `proc.cmdline`, `fd.sip` (destination IP), and `container.image.repository`. Example — a reverse-shell rule should check that `proc.name in (shell_binaries)` AND `fd.type=ipv4` AND `fd.sip != "127.0.0.1"` AND `container.image.repository` matches the demo app.
- **Scope by namespace**: use `k8s.ns.name = "demo"` so rules fire only against the target namespace, not `kube-system` or `argocd`.
- **Use macros**, don't inline conditions. Falco ships `shell_binaries`, `sensitive_files`, `container_started` macros — extend them, don't reinvent.
- **Exceptions before priority**: add explicit `exceptions:` for known-good `kubectl exec` sessions rather than raising the priority threshold and hiding real issues.
- **Test with the shipped `falco --list-plugins` and `falcoctl` linters** before deploying.
- **Priority `warning` for demo-critical rules, `notice` for exploration** — Falcosidekick filters at priority level, so mis-priority means alerts vanish.
- Author rules in a separate `custom-rules.yaml` mounted at `/etc/falco/rules.d/`, never edit `falco_rules.yaml` (upgrades overwrite it).

**Phase to address:** Runtime-detection phase; iterated during attack-simulation phase.
**Confidence:** MEDIUM (Falco rule-authoring gotchas are well documented in the falcosecurity/falco issue tracker, but not re-verified this session)

---

### Pitfall 7: ArgoCD sync loop / stuck `OutOfSync`
**Warning signs:**
- Application status flaps `Synced` ↔ `OutOfSync` every few seconds
- `argocd app diff` shows a field ArgoCD is repeatedly resetting (often `spec.replicas`, `image`, or annotations added by the cluster)
- `kubectl get events -n argocd` shows continuous "Updated" reconciliation actions

**What goes wrong:**
1. **Mutating admission webhook or HPA fights ArgoCD** — HPA sets `replicas`, ArgoCD sees drift, resets, repeat forever. Cluster-added annotations (Istio, kyverno, network operators) do the same.
2. **Manifest kustomize/helm output isn't deterministic** — e.g. helm templates that inject timestamps, or kustomize generators with `disableNameSuffixHash: false` producing new configmap names on every render.
3. **Auto-sync + auto-prune + a manifest error** creates rapid recreate loops.

**Prevention strategy:**
- Use `ignoreDifferences:` in the `Application` spec for fields owned by the cluster (`spec.replicas` if you use HPA; server-side-applied annotations; `metadata.annotations["deployment.kubernetes.io/revision"]`).
- `syncOptions: [ServerSideApply=true]` — reduces spurious drift on managed fields.
- Pin manifest generators: kustomize `disableNameSuffixHash: true` for demo-scale, or manage rolling with intentional new names.
- Disable auto-prune until the pipeline is stable; enable only after first successful sync.
- For helm charts: commit the rendered output to Git (or use `argocd app generate`) so ArgoCD compares a stable text.

**Phase to address:** GitOps phase, after first successful sync.
**Confidence:** MEDIUM

---

### Pitfall 8: `ImagePullBackOff` after Jenkins push — imagePullSecret missing or wrong tag
**Warning signs:**
- Pod stuck `ImagePullBackOff` or `ErrImagePull`
- `kubectl describe pod` says `unauthorized: authentication required` or `manifest unknown`
- ArgoCD shows `Synced` but pods are unhealthy (sync ≠ ready)

**What goes wrong:**
Three overlapping causes:
1. **Auth**: private registry needs `imagePullSecrets` on the ServiceAccount; without it, containerd anonymously requests and gets 401.
2. **Tag drift**: pipeline pushes `demo:abc123` but the manifest in Git still says `demo:latest` (or vice versa). ArgoCD faithfully applies the stale manifest.
3. **Case mismatch**: `Demo/App:tag` vs `demo/app:tag` — registries are case-sensitive; kubectl is not.

**Prevention strategy:**
- Bind `imagePullSecrets` to the default ServiceAccount in the demo namespace once via manifest (`kubectl patch serviceaccount default -p ...`), tracked in Git.
- Pipeline updates the manifest repo with the exact tag it pushed — use `yq` or `kustomize edit set image` in a "update manifest" stage. ArgoCD Image Updater is an alternative but adds moving parts a thesis doesn't need.
- Never use `:latest` in manifests — reproducibility disaster and Kubernetes cache can serve stale layers.
- After push, `curl -s http://<registry>/v2/demo/tags/list` to verify the tag exists before triggering ArgoCD sync.

**Phase to address:** First end-to-end pipeline demo phase.
**Confidence:** HIGH

---

### Pitfall 9: ArgoCD health checks flag healthy-but-slow apps as degraded
**Warning signs:**
- Application health `Degraded` even though `kubectl get pods` shows `Running 1/1`
- Custom resources (e.g. cert-manager Certificates) permanently `Progressing`
- Sync waves finish out of order

**What goes wrong:**
ArgoCD's built-in health checks are opinionated. For Deployments they check `availableReplicas == replicas` — slow startup (Trivy scanning a large image on startup, JVM warmup) causes false "degraded" during rollouts. For CRDs, if no health.lua script exists, status is `Unknown` and can be treated as unhealthy by `waitForHealth`.

**Prevention strategy:**
- Set demo app readiness/liveness probes with realistic `initialDelaySeconds` (10–30 s for Node.js/Python REST — the runtime is fast, but Trivy-scanning-on-start patterns can add seconds).
- Provide a `resource.customizations.health.<group>_<kind>` block in `argocd-cm` ConfigMap for any CRD you deploy; a 5-line Lua script returning `{ status = "Healthy" }` is fine for demo purposes.
- Use `syncOptions: [RespectIgnoreDifferences=true]` and sync waves (`argocd.argoproj.io/sync-wave` annotation) to order namespace → CRD → RBAC → workload.

**Phase to address:** GitOps phase.
**Confidence:** MEDIUM

---

### Pitfall 10: Trivy database update failures & Docker Hub rate limits
**Warning signs:**
- `TOOMANYREQUESTS: You have reached your pull rate limit` when Jenkins pulls `aquasec/trivy`
- `FATAL: failed to download vulnerability DB` — Trivy uses OCI artifacts on `ghcr.io/aquasecurity/trivy-db` (2026); rate limits or offline networks break scans
- Scans run but return 0 vulnerabilities on obviously vulnerable images (silent DB miss)

**What goes wrong:**
- **Rate limits**: unauthenticated pulls from Docker Hub / GHCR are throttled per source IP. From a home network doing 20 scans while debugging, you hit the ceiling.
- **DB cache eviction**: Trivy DB (~50 MB) redownloads on every fresh container unless a volume caches it.
- **Java/OS-specific DBs**: Trivy uses separate DBs for OS packages, Java, Node.js. If the language-specific DB fails, a vulnerable `package-lock.json` reports clean while OS layer reports fine — a silent false negative.
- **`--skip-db-update`** used carelessly means scanning against a month-old DB and missing new CVEs.

**Prevention strategy:**
- Pin Trivy image (`aquasec/trivy:0.55.0` or current) and pre-pull once, then use it locally.
- Persist Trivy cache: `-v trivy-cache:/root/.cache/trivy` on the agent.
- Configure `TRIVY_DB_REPOSITORY=public.ecr.aws/aquasecurity/trivy-db` as a fallback registry when GHCR rate-limits.
- Run `trivy image --download-db-only` in a nightly Jenkins job so demo runs never wait on DB fetch.
- Always scan with `--severity HIGH,CRITICAL --exit-code 1 --ignore-unfixed=false` and check exit code — silent 0 exit hides scan skips.
- Assert non-zero vulnerability count on a **known-vulnerable** image (e.g. `vulnerables/web-dvwa`) as a pipeline **test** — if Trivy ever reports clean on it, the DB is broken.
- For Docker Hub rate limits: `docker login` in Jenkins (free tier gets 200 pulls/6h authenticated vs 100 anonymous), or mirror to the local registry.

**Phase to address:** CI/Trivy phase; add smoke-test in a dedicated pipeline hardening step.
**Confidence:** HIGH on rate limits and cache; MEDIUM on 2026 DB registry URL — verify against `trivy --help` output before committing docs.

---

### Pitfall 11: Vulnerable demo app that doesn't actually demonstrate the vulnerability
**Warning signs:**
- SQL injection payload returns generic 500 error instead of leaking data — audience can't see the attack succeed
- CVE-loaded base image, but the vulnerable package isn't actually **called** by the app — Trivy flags it, runtime attack fails
- The vulnerability is patched by the OS package on rebuild ("worked yesterday" syndrome)
- Attack script needs to be run in a specific way; forgetting a flag makes it silently succeed against a mock, not the real app

**What goes wrong:**
- **CVE-in-image ≠ exploitable**: a base image reporting 300 CVEs may have zero that the app path exercises. Trivy blocks the build (good) but the runtime demo of "attacker exploits the CVE" fizzles.
- **Sanitized frameworks**: Node.js Express with `mysql2` parameterized queries won't be SQL-injectable even if you try. If you want SQL injection, you must deliberately concatenate strings and disable escaping.
- **Non-deterministic vulnerabilities**: `Math.random`-based auth, race conditions — attacks succeed sometimes; a live demo fails randomly.
- **Overkill**: DVWA / WebGoat include so many vulns that the audience loses focus. A thesis wants **one** clean, obvious vulnerability per demo scenario.

**Prevention strategy:**
- Build the vulnerable behaviour **intentionally and minimally**: one endpoint, string-concatenated SQL, `mysql` (not `mysql2`) client, no parameterisation. Comment the vulnerable line.
- Pin the base image to a specific old tag with a specific known CVE that the demo relies on (e.g. `node:14.0.0-alpine` for CVE-2021-XXXX). Trivy must consistently report it.
- **Pair Trivy findings with a runtime attack**: for each blocked CVE, have a script that exercises it *if* the block were bypassed. This makes the "shift-left saved us" narrative concrete.
- Pre-record a successful attack (asciinema or terminal recording) as a fallback for live-demo failure.
- Keep three separate demo scenarios; each demonstrates exactly one layer (Trivy blocks, ArgoCD deploys clean, Falco detects post-deploy attack). Do not mix vulnerabilities across scenarios.
- Deterministic attack scripts: hard-coded target URL, exit code that matches success/failure, no `sleep`-based timing.

**Phase to address:** Demo app phase and attack-simulation phase (co-designed).
**Confidence:** MEDIUM (based on general vulnerable-lab design, not tool-specific docs)

---

## Moderate Pitfalls

### Pitfall 12: JCasC secret handling — plaintext in Git
**What goes wrong:** developers paste registry passwords into `casc.yaml` and push to GitHub. Bots harvest within hours.
**Prevention:** Reference secrets via `${VAR}` in JCasC, inject through env vars from a `.env` file that is `.gitignore`d. Or use the JCasC `casc-secret-plugin` with a keystore. Document this in the README.

### Pitfall 13: k3s + Docker Desktop conflict on macOS
**What goes wrong:** Running Docker Desktop and Rancher Desktop simultaneously — both fight for the `docker` CLI symlink, and `kubectl` may point at the wrong context.
**Prevention:** Uninstall Docker Desktop before installing Rancher Desktop, or explicitly set `docker context use rancher-desktop`. Verify with `kubectl config current-context`.

### Pitfall 14: ArgoCD Application in wrong namespace
**What goes wrong:** `Application` CRs must live in the ArgoCD control-plane namespace (default `argocd`), but the deployed workloads go to a target namespace. Confusing the two causes "app not found" errors.
**Prevention:** Convention — put ArgoCD `Application` YAMLs under `bootstrap/argocd/`, workload YAMLs under `apps/<name>/`. Use the `app-of-apps` pattern.

### Pitfall 15: Trivy exit codes not enforced
**What goes wrong:** `trivy image demo:tag` runs successfully but the pipeline continues even though CRITICAL CVEs were found — the "block" never blocks.
**Prevention:** `trivy image --exit-code 1 --severity CRITICAL,HIGH demo:tag`, and in Jenkinsfile do NOT wrap in `|| true`. Test with a known-vulnerable image before trusting.

### Pitfall 16: Falco with Falcosidekick pointed at unreachable webhook
**What goes wrong:** Falcosidekick configured to POST to Slack / Discord / a UI. If unreachable (no internet, wrong URL), Falco keeps generating events but the demo has nowhere to display them — audience sees nothing.
**Prevention:** Deploy `falcosidekick-ui` locally (`--set falcosidekick.webui.enabled=true`) as the primary output; treat external webhooks as a nice-to-have. Confirm connectivity with `kubectl -n falco port-forward svc/falcosidekick-ui 2802`.

---

## Minor Pitfalls

### Pitfall 17: Manifest repo == source repo
**Symptom:** every code push triggers a GitOps sync even if no manifests changed; auditors can't tell "config change" from "code change."
**Prevention:** Separate manifest repo (or at minimum a separate `manifests/` folder that ArgoCD watches via `path:` filter).

### Pitfall 18: Timezone drift between host and VM
**Symptom:** Falco timestamps disagree with attack script logs by hours; correlation impossible.
**Prevention:** Rancher Desktop VM defaults to UTC — either set the host to UTC for the demo, or add `TZ=UTC` env var to Jenkins/Falco/app so all logs are UTC.

### Pitfall 19: `kubectl exec` used in demos triggers Falco alerts about your demo
**Symptom:** while demonstrating, you exec into a pod to show something; Falco flags it as anomalous.
**Prevention:** Add a Falco exception for `k8s.ns.name in (demo-namespace)` AND `proc.tty != 0` (interactive session) OR pre-record the demo section that requires exec.

### Pitfall 20: Missing `.dockerignore`
**Symptom:** `docker build` context is 500 MB, includes `.git`, `node_modules`, IDE files; build is slow and the image contains secrets in `.env`.
**Prevention:** `.dockerignore` with `node_modules`, `.git`, `.env*`, `*.log` — before the first `docker build`.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Environment bootstrap (k3s + registry) | Pitfall 2 (registry cross-network) | Use k3d registry from the start; document in setup guide |
| Jenkins CI | Pitfalls 1, 5, 12, 15 (socket, JCasC, secrets, exit codes) | JCasC + agent container + pinned plugin list on day 1 |
| Trivy integration | Pitfalls 10, 15 (DB updates, exit codes) | Persistent cache + known-vulnerable smoke-test image |
| Demo app | Pitfall 11 (vulnerability doesn't demonstrate) | Intentional, minimal, deterministic vulnerability |
| ArgoCD GitOps | Pitfalls 7, 8, 9, 14, 17 (sync loops, ImagePullBackOff, health, namespace, repo split) | Ignore-differences + tag-in-manifest updates + separate manifest path |
| Falco runtime | Pitfalls 3, 6, 16, 19 (driver, false positives, sink, self-triggered exec) | modern_ebpf + namespace-scoped rules + local UI sink |
| Attack simulation | Pitfalls 4, 11, 19 (RAM, non-demo-able vuln, self-alerts) | Serialize workloads; deterministic scripts |
| Final demo/thesis defence | Pitfall 4 (RAM), Pitfall 11 (live-demo failure) | Pre-recorded fallback; freeze system 24 h before |

---

## Sources

- **Project-internal:** `.planning/PROJECT.md` — Key Decisions section already encodes mitigations for Pitfalls 2, 3, 5 (k3d registry, modern_ebpf, JCasC).
- **Training-data knowledge:** Falco (falcosecurity/falco issue tracker patterns), ArgoCD (argoproj/argo-cd troubleshooting docs), Trivy (aquasecurity/trivy README + rate-limit history), Jenkins (JCasC + Docker-in-Docker anti-pattern discussions), Rancher Desktop (`containerd` + `registries.yaml` mechanics).
- **Not verified in this session:** WebSearch tool returned an environment error; WebFetch on Falco/ArgoCD upstream docs did not return troubleshooting content. Confidence levels above reflect this. Items marked MEDIUM should be re-verified against current 2026 docs during the corresponding phase's own research step.
- **Recommended verification URLs (for the phase-level researcher, not this session):**
  - https://falco.org/docs/rules/ (Falco rule syntax and macros)
  - https://argo-cd.readthedocs.io/en/stable/operator-manual/health/ (ArgoCD health checks)
  - https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/ (ignoreDifferences)
  - https://aquasecurity.github.io/trivy/ (Trivy DB and CLI)
  - https://docs.rancherdesktop.io/how-to-guides/adding-images-to-cluster/ (registry integration)
  - https://plugins.jenkins.io/configuration-as-code/ (JCasC secrets)
