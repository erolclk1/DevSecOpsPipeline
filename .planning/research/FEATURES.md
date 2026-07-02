# Feature Landscape — DevSecOps CI/CD Pipeline Thesis

**Domain:** Locally-runnable DevSecOps demonstration (Jenkins + Trivy + ArgoCD + Falco + k3s)
**Researched:** 2026-07-02
**Audience:** Master's thesis committee, ТУ-София, катедра "Киберсигурност"
**Overall confidence:** MEDIUM-HIGH (grounded in official Falco rule set + OWASP + DevSecOps conventions; some ecosystem specifics verified via Falco upstream rules repo)

---

## Framing: What "Complete" Means for This Thesis

A thesis demonstration is not a product. It must prove that **three security control layers** work together end-to-end:

1. **Shift-left (Build-time):** Trivy blocks vulnerable images before they reach the registry.
2. **GitOps policy (Deploy-time):** ArgoCD + admission policies reject non-compliant manifests.
3. **Runtime detection:** Falco observes and alerts on live attack behaviour inside the running cluster.

Every feature below is judged against a single question: **does it make one of those three layers observable, credible, and reproducible in a live demo?**

---

## Table Stakes

Features whose absence would leave the thesis incomplete or unconvincing to a defence committee.

### CI Pipeline (Jenkins + Trivy)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Declarative Jenkinsfile in demo-app repo | Reproducibility; committee expects pipeline-as-code | Low | Scripted pipeline is acceptable but declarative is standard |
| Build stage produces tagged image (git SHA, not `latest`) | Immutable artifacts are a DevSecOps baseline | Low | Feeds directly into GitOps manifest update |
| Trivy scan stage with `--severity HIGH,CRITICAL` gate | Core thesis claim: vulnerable images are blocked | Low | Exit code non-zero on findings; log full JSON report as build artifact |
| Explicit fail path: build stops, image NOT pushed | Demonstrates the gate; committee will ask to see a blocked build | Low | Scenario 1 of the three demo scenarios |
| Success path: image pushed to local registry, manifest repo updated | Demonstrates the happy path handoff to GitOps | Medium | Commit-and-push from Jenkins to manifest repo requires SSH key or PAT |
| Trivy SBOM output (CycloneDX or SPDX) archived per build | Supply-chain provenance is table stakes in 2026 | Low | `trivy image --format cyclonedx` — one extra flag |
| Build history visible in Jenkins UI during demo | Presenter must be able to show blocked vs passed builds side-by-side | Low | Retain last ~20 builds |

### GitOps Deployment (ArgoCD)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Separate manifest repo (or directory) from app source | Canonical GitOps pattern (app-of-apps or repo-per-env) | Low | Even a subfolder counts if pattern is documented |
| ArgoCD Application CR watching the manifest repo | The whole point of GitOps | Low | Auto-sync enabled with `prune: true`, `selfHeal: true` |
| Image tag in manifest driven by CI (never `latest`) | Ties CI success to deploy; provable chain of custody | Medium | Kustomize `newTag` field or `yq` in-place edit — pick one |
| At least one admission policy gate (see policy list below) | GitOps without policy is just `kubectl apply` in a loop | Medium | Kyverno is the pragmatic choice for a thesis |
| Sync status observable in ArgoCD UI during demo | Committee wants to see green/red state change | Low | Free with ArgoCD |
| Drift detection demonstration | Show ArgoCD reverting a manual `kubectl edit` | Low | Powerful, cheap thesis moment |

### Runtime Detection (Falco)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Falco deployed as DaemonSet with `modern_ebpf` driver | Required on Rancher Desktop (no kernel headers for kmod) | Medium | Already flagged in PROJECT.md |
| Default `falco_rules.yaml` loaded | Baseline coverage before custom rules | Low | Chart default |
| At least 3 custom rules targeting the demo attack scenarios | Custom rules prove the student understands Falco's DSL, not just Helm | Medium | See "Recommended Custom Rules" below |
| Structured JSON output to stdout | Machine-readable; enables downstream ingestion | Low | `json_output: true` in falco.yaml |
| Alerts visible in real time during demo (tail logs or UI) | If the committee can't see the detection fire, it didn't happen | Low | `kubectl logs -f -n falco -l app=falco` is sufficient for a thesis |

### Vulnerable Demo Application

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| SQL injection endpoint (string-concat query) | Already planned; canonical OWASP A03:2021 example | Low | Sqlite or a tiny local Postgres works |
| Command injection endpoint | Best single vulnerability for triggering Falco `run_shell_untrusted` | Low | `child_process.exec` with user input in Node.js; `os.system` in Python |
| Endpoint that returns stack traces / verbose errors | OWASP A05:2021 Security Misconfiguration; also useful for SQLi payloads | Low | One-liner: don't set `NODE_ENV=production` |
| Dockerfile with a deliberately outdated base (e.g., `node:16-alpine3.14` or `python:3.9-slim` from ~2022) | Guarantees Trivy finds CVEs — the whole demo depends on this | Low | Pin an old digest; document why |
| Runs as root in container (initially) | Enables demonstrating Kyverno `restricted` pod-security policy denials | Low | Then fix it and show the passing build for contrast |
| README documenting each vulnerability | Thesis artefact; also protects the student ("this is a lab, not negligence") | Low | Include OWASP references |

### Attack Simulation

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| SQL injection payload script (curl or Python `requests`) | Matches the app's primary vulnerability | Low | Extract dummy PII to make the impact concrete |
| Reverse-shell trigger (via command injection endpoint) | The single most compelling Falco demo | Low | `nc -e /bin/sh attacker 4444` from inside container |
| Suspicious process / privilege probe (e.g., `cat /etc/shadow`, `id`, `whoami`) | Fires multiple Falco rules in one scenario | Low | Trivial curl or `kubectl exec` |
| Scripts are idempotent and re-runnable | Live demos fail; must be able to re-trigger | Low | Wrap each scenario in a shell script under `attacks/` |
| Attack scripts refuse to run against non-local targets | Ethical safeguard; must appear in thesis text | Low | Hard-code `localhost` / cluster IP; document constraint |

### Documentation & Reproducibility

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| One-command bootstrap (`make up` or `./setup.sh`) | If the committee can't reproduce it, the thesis is weakened | High | Realistically: scripted install of Rancher Desktop preconditions + Helm installs |
| Architecture diagram (three layers, data flow) | Committee expects this in the defence slides | Low | Draw.io or Mermaid |
| Demo runbook (three scenarios, step-by-step) | Presenter aid; also thesis appendix | Low | Scenarios: (1) blocked build, (2) successful deploy, (3) attack detected |
| Teardown script | Practical: 16 GB laptop cannot leave everything running | Low | `helm uninstall` + `k3s ctr images prune` |

---

## Differentiators

Features that elevate the thesis from "meets requirements" to "distinction-worthy." Each is optional but each adds a defensible research contribution.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Cosign image signing + verification in ArgoCD/Kyverno** | Extends shift-left to supply-chain integrity; hot topic in 2026 (SLSA, Sigstore) | Medium | `cosign sign` in Jenkins, `verifyImages` policy in Kyverno |
| **Trivy scan of Kubernetes manifests (`trivy config`)** | Catches manifest-level misconfigurations before ArgoCD even sees them | Low | Second Trivy stage in Jenkins |
| **Falco → Falcosidekick → webhook / Slack / file** | Turns raw JSON logs into presentable alerts; makes the demo feel like a real SOC | Low-Medium | Falcosidekick is the canonical Falco output router |
| **Falcosidekick-UI (or a minimal grep dashboard)** | Visual timeline of detections during attack simulation — very presentation-friendly | Medium | UI is Helm-installable; costs ~200 MB RAM |
| **Metrics: MTTD (mean time to detect) per attack scenario** | Turns the demo into a quantifiable thesis result — chapter-worthy | Medium | Timestamp the attack script start vs the Falco alert emission |
| **Comparison table: with-gates vs without-gates** | Runs the same vulnerable image through a pipeline where Trivy is disabled — proves the gates matter | Low | Two Jenkinsfiles or a boolean parameter |
| **Kyverno policy report (PolicyReport CR)** | Shows which admission decisions were made and why; adds forensic depth | Low | Free once Kyverno is installed |
| **Second demo app (fixed version)** | Show the *same* pipeline succeeding when the vulnerabilities are removed | Low | Just a git branch of the vulnerable app |
| **Mapping of demo events to MITRE ATT&CK for Containers** | Standard cybersecurity framework — TU-Sofia committee will recognise it | Low | Table in thesis: T1059 Command Execution → Falco `run_shell_untrusted` |
| **SBOM diff between vulnerable and fixed build** | Visualises supply-chain remediation | Low | `cyclonedx-cli diff` or manual diff |
| **CIS Kubernetes Benchmark scan (`kube-bench`)** | Additional shift-left evidence for the cluster itself | Low | One-off Job manifest |
| **Rate-limited or resource-quota-exhausting DoS attack** | Fourth scenario: shows Falco + resource-limit policies working together | Medium | Optional; only if RAM budget allows |
| **Bilingual demo runbook (BG + EN)** | Serves TU-Sofia audience directly; small effort, real courtesy | Low | The thesis is in Bulgarian; the runbook can be too |

---

## Anti-Features

Features to explicitly NOT build. Each has a documented reason — the thesis must justify scope, not just requirements.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|--------------------|
| Cloud deployment (EKS/GKE/AKS) | Out of scope per PROJECT.md; adds cost, latency, and account setup with zero thesis value | Local k3s only; note portability in thesis future work |
| Multi-node k3s / HA control plane | Doubles RAM budget; demonstrates operations, not security | Single-node; explicitly justify in constraints chapter |
| Full OWASP Juice Shop | Excellent teaching app but has ~40 vulnerabilities — too much surface for a focused thesis | Handful of targeted vulnerabilities in a small custom app |
| OWASP ZAP active scan in CI | Out of scope per PROJECT.md; slow; DAST duplicates attack scripts for demo purposes | Attack simulation scripts cover the same demonstration ground |
| Paid SAST/SCA (Snyk, Mend, Checkmarx) | Out of scope; Trivy covers container scanning; adding SAST expands scope without adding thesis novelty | Note in thesis that Trivy is sufficient for the container attack surface being demonstrated |
| SIEM integration (Splunk, ELK) | Weeks of setup for a demo that a `tail -f` accomplishes | Falcosidekick stdout / file / webhook is enough |
| Service mesh (Istio, Linkerd) | Would enable mTLS demos but eats 1-2 GB RAM and complicates every other layer | Note as future work; NetworkPolicy is a cheaper substitute if network isolation must be shown |
| Terraform / Ansible for infra | The infra IS the demo — everything is Helm and kubectl on a laptop | Bash + Helm + one Makefile |
| Custom-built vulnerability database | Trivy's DB is authoritative and free | Consume Trivy DB; do not re-invent |
| eBPF-authored custom probes | Falco's `modern_ebpf` driver already provides eBPF-based syscall visibility; writing raw eBPF is a separate thesis | Write Falco rules, not eBPF programs |
| Zero-trust / SPIFFE identity | Adjacent to DevSecOps but a separate thesis in its own right | Mention as adjacent work |

---

## Recommended Falco Custom Rules (Answering Question 2)

These are the highest-signal rules for a thesis demo. All build on Falco's default macros. Confidence: MEDIUM-HIGH (rule names and structure verified against the upstream `falcosecurity/rules` repo; exact syntax should be double-checked against the Falco version pinned in the Helm chart).

| Rule | Detects | Why It Matters for the Demo | Base Rule to Extend |
|------|---------|------------------------------|---------------------|
| **Reverse shell in container** | `nc -e`, `bash -i`, `/dev/tcp/*` redirection | Most cinematic detection; direct response to command injection | Default: *Netcat Remote Code Execution in Container* |
| **Shell spawned by web server / DB process** | Any `bash`/`sh`/`ash` whose parent is `node`, `python`, `postgres`, `nginx` | Fires immediately on command-injection RCE — this is the money shot | Default: *Run shell untrusted* |
| **Read sensitive file** | `cat /etc/shadow`, `cat /etc/sudoers`, `.ssh/*` | Post-exploitation reconnaissance; pairs beautifully with the reverse shell scenario | Default: *Read sensitive file untrusted* |
| **Unexpected outbound network connection** | Egress from the demo pod to any IP not in an allow-list | Detects data exfiltration / C2 callback | Default: *Unexpected outbound connection destination* (needs profiling) |
| **Package management inside container** | `apt`, `apk`, `yum`, `pip install` at runtime | Classic attacker persistence (installing tools); low false-positive in an immutable image | Default: *Launch Package Management Process in Container* |
| **Privilege escalation attempt** | Setuid syscalls; `sudo` executed by non-root context | Direct thesis-relevant category | Default: *Sudo Potential Privilege Escalation* / *Set Setuid or Setgid bit* |
| **Contact K8s API server from application pod** | Application pod attempting to hit `kubernetes.default.svc` | Detects lateral movement / cluster reconnaissance | Default: *Contact K8S API Server From Container* |
| **Clear log activity** | `truncate`, `> /var/log/*`, `shred` | Anti-forensics; adds depth to the thesis chapter on detection | Default: *Clear Log Activities* |

**Recommendation:** Ship **five** custom rules — reverse shell, shell-from-webapp, sensitive-file read, package management, K8s API contact. Reference the other three defaults in the thesis text without disabling them.

---

## Recommended Vulnerable Endpoints (Answering Question 4)

SQL injection is planned. Add these to broaden the demo without bloating the app:

| Vulnerability | OWASP 2021 Cat. | Why Add | What It Enables |
|---------------|------------------|---------|-----------------|
| SQL injection (planned) | A03 Injection | Baseline demo | Data exfiltration payload; trivial Trivy-independent proof of exploitation |
| **Command injection** | A03 Injection | Highest-value addition | Triggers reverse-shell scenario → Falco fires → the whole three-layer story lands in one attack |
| **Broken authentication** (hard-coded JWT secret or plaintext-password endpoint) | A07 Identification & Auth Failures | Trivy `misconfig` / secret scan detects hard-coded secrets in source or image layers | Ties Trivy to app-level flaws, not just OS CVEs |
| **Server-Side Request Forgery (SSRF)** | A10 SSRF | Endpoint that fetches arbitrary URL | Enables demonstrating egress control / NetworkPolicy / Falco unexpected-outbound rule |
| **Vulnerable dependency** (e.g., old `lodash`, `requests`, `flask`) | A06 Vulnerable Components | Ensures Trivy `fs` / `image` scan finds application-layer CVEs, not just base-image CVEs | Distinguishes OS-package findings from language-package findings — a subtlety worth a thesis paragraph |
| **Verbose error / stack trace** | A05 Security Misconfiguration | Free — just don't set `NODE_ENV=production` | Assists SQLi exploitation during the live demo (attacker sees the error) |

**Do NOT add:** XSS (this is a REST API — no browser context), CSRF (no session cookies), XML External Entity (no XML parser). They dilute focus without adding thesis value.

---

## Standard GitOps Policy Gates (Answering Question 5)

Kyverno is recommended over OPA/Gatekeeper for a thesis: policies are YAML (not Rego), which is more legible for a defence committee. Confidence: MEDIUM (policy names below correspond to well-known Kyverno community policies; exact policy YAML should be pulled from `kyverno/policies` and version-pinned).

| Policy | Blocks | Thesis Value |
|--------|--------|--------------|
| **disallow-latest-tag** | Any image tagged `:latest` or untagged | Enforces immutable-tag principle; ties directly to CI (which produces SHA tags) |
| **restrict-image-registries** | Images from any registry not in the allow-list (local registry only) | Demonstrates supply-chain trust boundary |
| **verify-image-signatures** (Cosign) | Unsigned images | Differentiator; requires signing stage in Jenkins |
| **disallow-privileged-containers** | `securityContext.privileged: true` | Classic pod-security policy; overlaps with Falco runtime detection story |
| **disallow-run-as-root** | Containers without `runAsNonRoot: true` | Complements the "app initially runs as root" demo — the policy denial IS the lesson |
| **require-resource-limits** | Pods without CPU/memory `limits` | Defends the cluster against DoS in the runtime demo scenario |
| **disallow-host-namespaces** | `hostNetwork`, `hostPID`, `hostIPC` | Baseline container isolation |
| **disallow-capabilities** | Non-default Linux capabilities (e.g., `NET_ADMIN`, `SYS_ADMIN`) | Fine-grained privilege minimisation |
| **require-readonly-rootfs** | Writable container filesystems | Prevents attacker persistence; overlaps with Falco package-management rule |

**Recommendation:** Ship **four** policies as table stakes — `disallow-latest-tag`, `restrict-image-registries`, `disallow-privileged-containers`, `require-resource-limits`. Add `verify-image-signatures` if Cosign is adopted (differentiator).

---

## Reporting / Alerting Outputs for Falco Detections (Answering Question 6)

Ranked by demo impact vs setup cost.

| Output | Setup | Demo Impact | Recommendation |
|--------|-------|-------------|----------------|
| `kubectl logs -f` on the Falco DaemonSet | Zero | Low — walls of JSON | Baseline only |
| Falco stdout with `json_output: true` piped through `jq` | Trivial | Medium — filterable in real time | Ship this for the CLI-only variant |
| **Falcosidekick → file output** | ~5 minutes (Helm value) | Medium — clean per-event JSON files | Ship for archival / thesis appendix |
| **Falcosidekick → webhook** to a local receiver | ~15 minutes | High — allows a live-updating web page | Good differentiator |
| **Falcosidekick-UI** (dedicated dashboard) | Helm install; ~200 MB RAM | Very high — timeline visual for defence slides | Ship if RAM budget allows |
| Falcosidekick → Slack / Teams | ~10 minutes with a personal workspace | High — feels like a real SOC | Optional; nice for slide screenshots |
| Falcosidekick → Prometheus/Grafana | ~1 hour + resource cost | High but overkill for a thesis | Skip unless metrics chapter is core |
| Falcosidekick → SIEM (ELK/Splunk) | Days | High but massively out of scope | Skip |

**Recommendation:** Ship **Falcosidekick + file output + UI**. Total added RAM ~250 MB. This gives (a) a live visual for the defence, (b) archival JSON for the thesis appendix, and (c) shows the student understands the Falco output ecosystem beyond the DaemonSet.

---

## Compelling Attack Simulation Scenarios (Answering Question 3)

Ranked by narrative impact and detection coverage. Ship the top three as the mandatory demo trio; keep the others as bonus material.

### Scenario A — Blocked Build (CI layer)
1. Attempt to promote the vulnerable image with a Trivy `HIGH` gate.
2. Jenkins fails; image is never pushed.
3. Show the Trivy report (CVE IDs, CVSS scores).

**Layers exercised:** CI. **Duration:** ~2 min. **Slide potential:** high.

### Scenario B — Successful Deploy After Remediation (CI + GitOps)
1. Switch to `fixed` branch of the app (updated base image + pinned deps).
2. Trivy passes; image pushed; manifest repo updated; ArgoCD syncs.
3. Show the green ArgoCD Application and the passing Kyverno policy report.

**Layers exercised:** CI + GitOps. **Duration:** ~3 min. **Slide potential:** high.

### Scenario C — Live Attack Detected (Runtime)
1. From the attacker script, POST a command-injection payload that opens a reverse shell.
2. Inside the reverse shell: `cat /etc/shadow`, `apk add curl`, callback to attacker IP.
3. Falcosidekick UI shows five alerts within seconds: reverse-shell, sensitive-file read, package management, unexpected outbound, shell-from-web-server.

**Layers exercised:** Runtime. **Duration:** ~2 min. **Slide potential:** highest — this is the money moment.

### Scenario D (Differentiator) — Policy Denial at Admission
1. Push a manifest with `privileged: true` and `image: nginx:latest` directly to the manifest repo.
2. ArgoCD tries to sync; Kyverno denies both violations.
3. Show the PolicyReport CR listing the denial reasons.

**Layers exercised:** GitOps. **Duration:** ~2 min. **Slide potential:** medium — proves the policy layer is not decorative.

### Scenario E (Differentiator) — Drift Correction
1. `kubectl edit deployment demo-app` to change the image tag to a known-vulnerable one.
2. ArgoCD detects drift within its sync interval and reverts.
3. Falco (if the vulnerable pod started) also flags the anomalous behaviour.

**Layers exercised:** GitOps + Runtime. **Duration:** ~2 min. **Slide potential:** medium.

### Scenario F (Bonus) — Cryptominer Simulation
1. Reverse shell downloads and runs a fake cryptominer binary (a busy-loop, not a real miner).
2. Falco fires on unexpected binary execution + unexpected outbound + high CPU signal.

**Layers exercised:** Runtime. **Duration:** ~2 min. **Slide potential:** high but overlaps with Scenario C — pick one.

---

## Feature Dependencies

```
Vulnerable demo app  ──▶  Dockerfile / build
        │
        └──▶  Jenkins CI  ──▶  Trivy scan  ──▶  (pass) push image
                                       │
                                       └──▶  (pass) update manifest repo
                                                       │
                                                       └──▶  ArgoCD sync  ──▶  Kyverno admission
                                                                                       │
                                                                                       └──▶  Running pod  ──▶  Falco (+ Falcosidekick)
                                                                                                                      │
Attack scripts  ─────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Every layer depends on the one above. This is why phase ordering matters: build bottom-up (app → CI → registry → GitOps → runtime), never top-down.

---

## MVP Recommendation

For the thesis defence, in priority order:

1. Vulnerable demo app with SQL injection **and** command injection.
2. Jenkins pipeline with Trivy image scan and hard gate.
3. Local registry + manifest repo + ArgoCD auto-sync.
4. Four Kyverno policies (latest-tag, registry allow-list, privileged, resource limits).
5. Falco with `modern_ebpf` + five custom rules.
6. Three attack scenarios (blocked build, successful deploy, live attack).
7. Falcosidekick with file output (add UI only if time permits).
8. One-command bootstrap script + demo runbook.

**Defer without regret:** Cosign signing, kube-bench, MTTD metrics, cryptominer scenario. Each is a differentiator, not a table stake.

---

## Confidence Notes

- **Falco rule names** — verified against `falcosecurity/rules` upstream (HIGH).
- **Kyverno policy list** — based on Kyverno community policies; exact CR YAML should be pulled and version-pinned before implementation (MEDIUM).
- **OWASP mappings** — from OWASP Top 10 2021 (still the reference standard in July 2026; a 2025 revision is in progress per OWASP but not yet dominant) (MEDIUM).
- **Falcosidekick RAM figures** — order-of-magnitude estimate from training data (LOW-MEDIUM; verify against Helm chart resource requests during Phase X).
- **Attack scenario timings** — presenter's estimate; will vary with laptop performance (LOW).

## Sources

- [Falco upstream rule set](https://github.com/falcosecurity/rules/blob/main/rules/falco_rules.yaml) — verified rule names for reverse shell, shell-untrusted, sensitive-file, K8s-API-contact rules (HIGH)
- [Falco documentation — outputs and Falcosidekick](https://falco.org/docs/alerts/) — output channels (MEDIUM, training data)
- [Kyverno policies catalogue](https://kyverno.io/policies/) — reference for policy names (MEDIUM, page structure verified)
- [OWASP Top Ten Web Application Security Risks](https://owasp.org/www-project-top-ten/) — vulnerability categories (HIGH)
- [Trivy documentation](https://aquasecurity.github.io/trivy/) — scan modes, SBOM output (MEDIUM, training data)
- [ArgoCD user guide — sync and drift](https://argo-cd.readthedocs.io/) — auto-sync, self-heal (MEDIUM, training data)
- [MITRE ATT&CK for Containers](https://attack.mitre.org/matrices/enterprise/containers/) — for tactical mapping in thesis (MEDIUM, training data)
