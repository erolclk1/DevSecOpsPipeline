# Demo Script — Thesis Committee Presentation

**Thesis title:** DevSecOps CI/CD Pipeline for Automated Vulnerability Detection and Runtime Security  
**Total demo time:** ~15 minutes (3 scenarios × 4–5 min each)  
**Institution:** ТУ-София, катедра "Киберсигурност"

---

## Pre-Demo Checklist (Run BEFORE the committee sits down)

```bash
make demo-warmup
```

Wait for: `✓ Stack warm. Ready for demo.`

Also open these in separate browser tabs (do this now — not during the demo):
- Jenkins: http://localhost:8080
- ArgoCD: https://localhost:8443 (accept the self-signed cert warning)
- Falcosidekick UI: http://localhost:2802 (start port-forward: `kubectl port-forward svc/falco-falcosidekick-ui -n falco 2802:2802`)

Have a terminal ready. Demo is sequential — run Scenario 1 first, then 2, then 3.

---

## Scenario 1: Shift-Left Security — Blocked Build (~4 minutes)

**Говорете:** (What to say)  
*"Първият защитен слой е shift-left сигурността. Trivy сканира контейнерния образ по време на build в Jenkins — преди да бъде изпратен в регистъра."*  
*"The first security layer is shift-left. Trivy scans the container image at build time in Jenkins — before it is ever pushed to the registry."*

**Step 1 — Run the demo:**
```bash
make demo-1
```

**Step 2 — Wait:** ~2–4 minutes. Jenkins builds and runs Trivy.

**Step 3 — Show in Jenkins UI:**  
Point at the pipeline view. The **SCAN stage is red**. The PUSH and BUMP stages are greyed out.

**Step 4 — Show CVE output:**  
Click the failed build → Console Output. Scroll to the Trivy table showing HIGH and CRITICAL CVEs.

**Step 5 — Prove the image was NOT pushed:**
```bash
curl -s http://localhost:5001/v2/demoapp/tags/list
```
Output shows only the old tag. No new SHA was added.

**Say:** *"The pipeline failed at the SCAN stage. The vulnerable image never touched the registry. No deployment was possible."*

**Pass check:** Jenkins build status = FAILURE, SCAN stage red, no new image tag in registry.

---

## Scenario 2: GitOps Pipeline — Successful Deploy (~5 minutes)

**Говорете:**  
*"Вторият слой — GitOps с ArgoCD и Kyverno. При чист образ, целият pipeline е зелен и ArgoCD автоматично синхронизира промяната в клъстера."*  
*"The second layer is GitOps: ArgoCD and Kyverno. With a clean image, the entire pipeline goes green and ArgoCD automatically syncs the change to the cluster."*

**Step 1 — Run the demo:**
```bash
make demo-2
```

**Step 2 — Wait:** ~4–6 minutes. Jenkins build + ArgoCD sync.

**Step 3 — Show in Jenkins UI:**  
All 4 stages green: **BUILD → SCAN → PUSH → BUMP**.

**Step 4 — Show the Git commit:**
```bash
git log --oneline -3
```
The top commit is: `ci: bump demoapp to <sha> [skip ci]` — written by Jenkins, never by a human running `kubectl`.

**Step 5 — Show in ArgoCD UI:**  
Application `demoapp` shows **Synced / Healthy**. Click the app → the new pod SHA is visible.

**Step 6 — Show Kyverno PolicyReport (optional bonus):**
```bash
kubectl get policyreport -n demoapp -o wide
```
Shows the 4 policies evaluated the new pod and accepted it (SHA tag, not `:latest`).

**Say:** *"Jenkins never ran kubectl apply. ArgoCD is the only entity that touches the cluster. This is the GitOps boundary."*

**Pass check:** 4 green stages, bump commit in git log, new pod SHA in ArgoCD.

---

## Scenario 3: Runtime Security — Live Attack Detected (~3 minutes)

**Говорете:**  
*"Третият слой — runtime детекция с Falco. Дори ако атакуващ достигне до работещия контейнер, Falco засича системните извиквания и генерира именувани предупреждения."*  
*"The third layer is runtime detection with Falco. Even if an attacker reaches the running container, Falco detects the syscalls and generates named alerts."*

> **IMPORTANT:** Wait for Scenario 2 to fully complete before starting Scenario 3.

**Step 1 — Prepare the Falcosidekick UI:**  
Switch to the browser tab with http://localhost:2802. The events list should currently be empty (or have old events).

**Step 2 — Run the demo:**
```bash
make demo-3
```

**Step 3 — Watch the Falcosidekick UI in real time:**  
Within ~5–10 seconds of each attack script running, alerts appear in the webui. Point at:
- `reverse-shell` or `shell-from-webapp` alert (from `reverse_shell.sh`)
- `read-sensitive-file` alert (from `privilege_probe.sh` — `cat /etc/shadow`)
- `package-management-in-container` alert (from `privilege_probe.sh` — `apk add curl`)

**Step 4 — Show the log file:**
```bash
tail -20 logs/falco.log
```
Shows the JSON-structured alert events, timestamped, persisted.

**Step 5 — Show namespace scoping (optional bonus):**
```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "rule\|demoapp"
```
Only `demoapp` namespace events appear — ArgoCD/kube-system generate zero alerts.

**Say:** *"Three distinct attacks, three named Falco rules, all alerts within 30 seconds — and they are persisted to the log file even after the pod restarts."*

**Pass check:** ≥3 distinct rule names in Falcosidekick webui, `logs/falco.log` contains events with `k8s.ns.name: demoapp`.

---

## Fallback Procedures

### If Jenkins build takes more than 10 minutes

Jenkins may be waiting for the agent to provision. Check:
```bash
docker logs jenkins-controller 2>&1 | tail -20
```
If the agent is not connecting, restart: `make reset-jenkins && make demo-1`

### If Falcosidekick webui is blank during demo-3

Port-forward may have dropped. Restart in a new terminal:
```bash
kubectl port-forward svc/falco-falcosidekick-ui -n falco 2802:2802
```
The log file is the primary evidence: `tail -20 logs/falco.log`

### If ArgoCD does not sync after demo-2

Force a sync:
```bash
kubectl annotate application demoapp -n argocd argocd.argoproj.io/refresh=hard
```

---

## Questions to Expect from the Committee

**Q: Защо не използвате cloud provider?**  
A: Thesis is designed for local reproducibility. The architecture maps directly to any cloud CI/CD — the tools (Jenkins, ArgoCD, Falco) are cloud-native and deployed the same way in production.

**Q: Trivy ли е достатъчен за production?**  
A: Trivy covers OS packages, language dependencies, and IaC misconfigs. For a production pipeline, you would add SBOM signing (Cosign) and SBOM diffing — the foundation demonstrated here is the same.

**Q: Как Falco знае кой процес е опасен?**  
A: Falco uses eBPF to hook syscalls at the kernel level. The custom rules define conditions (e.g., `proc.name = bash AND proc.pname = node`) that signal anomalous behaviour. All rules are scoped to the `demoapp` namespace to prevent false positives.
