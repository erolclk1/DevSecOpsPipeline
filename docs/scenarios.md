# Demo Scenarios — DevSecOps Pipeline Thesis

Three scenarios that demonstrate the three security control layers.

> **Before any scenario:** Run `make demo-warmup` to pre-warm the Trivy DB and verify all components.
> **Scenarios are sequential.** Do not run `demo-2` and `demo-3` concurrently — RAM budget is 10 GB total.

---

## Scenario 1: Shift-Left Security — Blocked Build

**What this proves:** A vulnerable container image is automatically blocked by Trivy *before* it ever reaches the registry. The pipeline fails at the SCAN stage and no new image tag is pushed.

**Security layer:** Shift-left (Trivy in Jenkins CI)

### Prerequisites

- Jenkins running at http://localhost:8080
- Registry running (`docker ps --filter name=registry`)
- Trivy DB warmed (`make demo-warmup`)

### Run

```bash
make demo-1
```

### Expected Output

```
── Demo Scenario 1: Blocked Build ───────────────────────────────────
[scenario-1.sh] Triggering vulnerable build in Jenkins...
[scenario-1.sh] Waiting for Jenkins build to start...
[scenario-1.sh] Build #N started. Polling for SCAN stage result...
[Jenkins SCAN stage] trivy image --severity HIGH,CRITICAL --exit-code 1 ...
Total: 12 (HIGH: 8, CRITICAL: 4)
┌───────────────┬────────────────┬──────────┬──────────────┐
│  Library      │ Vulnerability  │ Severity │ Installed Ver│
├───────────────┼────────────────┼──────────┼──────────────┤
│ openssl       │ CVE-XXXX-XXXX  │ CRITICAL │ ...          │
└───────────────┴────────────────┴──────────┴──────────────┘
[scenario-1.sh] ✓ SCAN stage failed as expected (exit code 1)
[scenario-1.sh] ✓ Verifying no new image tag pushed...
[scenario-1.sh] ✓ Registry tags unchanged — image was NOT pushed
```

**Timing:** ~2–4 minutes (Jenkins queue + Trivy scan with warm DB).

### What to Observe in UI

1. Open **Jenkins** at http://localhost:8080 → pipeline view shows **SCAN stage in red**.
2. The PUSH and BUMP stages are greyed out — they never ran.
3. Run: `curl -s http://localhost:5001/v2/demoapp/tags/list` — only the old tag, no new one.

### Pass Criteria

- Jenkins build ends with FAILURE status at SCAN stage
- `curl http://localhost:5001/v2/demoapp/tags/list` shows no new tag with a recent SHA

---

## Scenario 2: GitOps Pipeline — Successful Deploy

**What this proves:** A fixed image passes Trivy, is pushed to the registry, and ArgoCD automatically deploys it to the cluster — no human runs `kubectl apply` at any point.

**Security layer:** GitOps (ArgoCD auto-sync + Kyverno admission control)

### Prerequisites

- Jenkins running at http://localhost:8080
- ArgoCD running (`kubectl get pods -n argocd`)
- Scenario 1 complete (demonstrates the contrast)

### Run

```bash
make demo-2
```

### Expected Output

```
── Demo Scenario 2: Successful Deploy ───────────────────────────────
[scenario-2.sh] Triggering fixed build in Jenkins...
[scenario-2.sh] Build #N started. Polling stages...
[Jenkins BUILD stage]  ✓ docker build ... (tag: <sha>)
[Jenkins SCAN stage]   ✓ Trivy: 0 HIGH, 0 CRITICAL (exit 0)
[Jenkins PUSH stage]   ✓ Pushed demoapp:<sha> to host.rancher-desktop.internal:5001
[Jenkins BUMP stage]   ✓ Updated deploy/overlays/local/demoapp-patch.yaml → <sha>
                        ✓ Committed: "ci: bump demoapp to <sha> [skip ci]"
[scenario-2.sh] Waiting for ArgoCD to sync (up to 90 s)...
[scenario-2.sh] ✓ ArgoCD: Synced / Healthy
[scenario-2.sh] ✓ New pod running with image tag: <sha>
```

**Timing:** ~4–6 minutes (Jenkins build + Trivy + ArgoCD sync ~30–60 s).

### What to Observe in UI

1. **Jenkins** at http://localhost:8080 → all 4 stages (BUILD / SCAN / PUSH / BUMP) green.
2. **ArgoCD** at https://localhost:8443 → application `demoapp` shows **Synced / Healthy** with the new SHA.
3. Verify in Git: `git log --oneline -3` shows a `ci: bump demoapp to <sha> [skip ci]` commit.

### Pass Criteria

- All 4 Jenkins stages green (BUILD / SCAN / PUSH / BUMP)
- `git log --oneline -1` shows a `[skip ci]` bump commit
- `kubectl get pods -n demoapp` shows a pod with the new image SHA
- ArgoCD UI shows Synced / Healthy

### Kyverno Admission Control (Bonus Demo Point)

To demonstrate Kyverno policy enforcement during the ArgoCD sync:

```bash
kubectl get policyreport -n demoapp -o wide
```

The PolicyReport shows admission decisions for the new pod. The `disallow-latest-tag` policy confirms the SHA tag was accepted.

---

## Scenario 3: Runtime Security — Live Attack Detected

**What this proves:** Cyberattacks against the running application trigger named Falco alerts within 30 seconds, persisted to a log file via Falcosidekick.

**Security layer:** Runtime detection (Falco with modern_ebpf + Falcosidekick)

### Prerequisites

- Falco running: `kubectl get pods -n falco` shows Running
- Demo app deployed: `kubectl get pods -n demoapp` shows Running
- Scenario 2 complete (app is on the latest version)

> **Important:** Do NOT start `demo-3` while a Jenkins build from `demo-2` is still running. Wait for `demo-2` to fully complete. Running both simultaneously approaches the 10 GB RAM ceiling.

### Setup: Start Falcosidekick Web UI (in a separate terminal)

```bash
kubectl port-forward svc/falco-falcosidekick-ui -n falco 2802:2802
```

Open http://localhost:2802 in a browser. Keep this terminal running.

### Run

```bash
make demo-3
```

### Expected Output

```
── Demo Scenario 3: Live Attack Detected ─────────────────────────────
[sqli.py]              Running SQL injection against /sqli endpoint...
[sqli.py]              ✓ Extracted data: [{"id":1,"name":"alice"}, ...]
[reverse_shell.sh]     Triggering command injection → reverse shell attempt...
[reverse_shell.sh]     ✓ Shell spawned (Falco will detect proc.name=bash child of node)
[privilege_probe.sh]   Executing privilege probe inside demoapp pod...
[privilege_probe.sh]   ✓ cat /etc/shadow attempted (Falco: read-sensitive-file)
[privilege_probe.sh]   ✓ apk add curl attempted (Falco: package-management-in-container)

Copying Falco alert log out of the WSL2 VM...
✓ logs/falco.log updated (N lines)

Check Falco alerts:
  Logs: kubectl logs -f -n falco -l app.kubernetes.io/name=falco
  UI:   kubectl port-forward svc/falco-falcosidekick-ui -n falco 2802:2802
  File: tail -20 logs/falco.log
```

**Timing:** ~60–90 seconds for all three scripts. Falco alerts appear within ~5 seconds of each attack.

### What to Observe in UI

1. **Falcosidekick Web UI** at http://localhost:2802 → events appear in real time:
   - `reverse-shell` alert (or `shell-from-webapp`)
   - `read-sensitive-file` alert
   - `package-management-in-container` alert
2. All alerts show `rule`, `priority: WARNING` or `CRITICAL`, and `k8s.ns.name: demoapp`.
3. File evidence: `tail -20 logs/falco.log`

### If the WSL2 log copy-out fails

The `wsl -d rancher-desktop` command requires the WSL2 distribution name to match. If you see "(run the copy-out manually on the target if wsl CLI is unavailable)", use:

```bash
kubectl exec -n falco $(kubectl get pod -n falco -l app.kubernetes.io/name=falcosidekick -o jsonpath='{.items[0].metadata.name}') \
    -- cat /var/log/falco/events.log
```

### Pass Criteria

- `tail -20 logs/falco.log` contains at least 3 distinct rule names: `reverse-shell` (or `shell-from-webapp`), `read-sensitive-file`, `package-management-in-container`
- Falcosidekick webui shows alerts with `output_fields.k8s.ns.name: demoapp`
- All alerts timestamped within 30 seconds of the attack scripts finishing

---

## Quick Reference

| Scenario | Command | Proves | Duration |
|----------|---------|--------|----------|
| 1 — Blocked Build | `make demo-1` | Trivy shift-left blocks CVEs | ~3 min |
| 2 — Successful Deploy | `make demo-2` | GitOps end-to-end pipeline | ~5 min |
| 3 — Live Attack | `make demo-3` | Runtime Falco detection | ~2 min |

**Total demo time (sequential):** ~10–15 minutes excluding warmup.
