---
phase: 05-runtime-security
plan: 03
type: execute
wave: 2
depends_on: ["05-01", "05-02"]
files_modified:
  - falco/verify-phase5.sh
  - logs/.gitkeep
  - .gitignore
  - Makefile
autonomous: false
requirements: [FALCO-02, FALCO-04, FALCO-05, ATK-01, ATK-02, ATK-03]

must_haves:
  truths:
    - "A single command (make verify-phase-5) installs Falco and runs all 3 attacks; for ATK-02/ATK-03 it asserts named Falco alerts within 30 seconds, and for ATK-01 it asserts sqli.py exits 0 deterministically (proof of SQL injection data extraction — no Falco alert is expected, because the SQL runs inside the Node.js process, not as a detectable syscall/spawn)"
    - "Alerts persist to /var/log/falco/events.log on the node and survive a Falco pod restart"
    - "A full Jenkins->ArgoCD cycle produces ZERO demo-tagged Falco alerts (namespace scoping verified)"
    - "logs/falco.log can be copied out of the WSL2 VM for viewing without committing runtime logs to git"
    - "make demo-3 runs all three attack scripts and points the operator at the webui + persisted log"
  artifacts:
    - path: "falco/verify-phase5.sh"
      provides: "Full phase-5 suite: install/driver check, 3 attacks, alert-within-30s, persistence-after-restart, zero-alert-in-normal-ops"
      contains: "verify-rules-loaded"
    - path: "logs/.gitkeep"
      provides: "Keeps logs/ dir in git without committing runtime falco.log"
    - path: ".gitignore"
      provides: "Ignores logs/falco.log (runtime artifact)"
      contains: "logs/falco.log"
    - path: "Makefile"
      provides: "verify-phase-5 target + demo-3 wired to all 3 attacks + log copy-out"
  key_links:
    - from: "falco/verify-phase5.sh"
      to: "attacks/*.sh + attacks/sqli.py + falco/verify-rules-loaded.sh"
      via: "invokes each attack, then greps kubectl logs / events.log for the named rules within 30s"
      pattern: "attacks/reverse_shell.sh"
    - from: "Makefile verify-phase-5"
      to: "falco/verify-phase5.sh"
      via: "bash falco/verify-phase5.sh"
      pattern: "verify-phase5.sh"
---

<objective>
Wire the end-to-end Phase 5 verification: a full-suite script that installs/checks Falco,
runs all three attacks, asserts named alerts within 30s, proves persistence across a pod
restart, and confirms zero alerts during normal pipeline operation. Then run it on the
Windows/WSL2 Rancher Desktop target as a human-verified checkpoint.

Purpose: This is the Scenario-3 acceptance gate for the whole phase — it proves the runtime
detection layer actually detects attacks and persists evidence.
Output: falco/verify-phase5.sh, logs/.gitkeep, .gitignore entry, Makefile verify-phase-5 +
demo-3 wiring, and a green run on the target.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/phases/05-runtime-security/05-RESEARCH.md
@CLAUDE.md
@falco/values.yaml
@falco/rules/custom-rules.yaml
@falco/verify-rules-loaded.sh
@attacks/sqli.py
@attacks/reverse_shell.sh
@attacks/privilege_probe.sh
@app/verify.sh

<interfaces>
<!-- From 05-01 / 05-02 outputs + confirmed target facts. -->
- Falco pod selector: `-l app.kubernetes.io/name=falco -n falco`.
- Falcosidekick services: `falco-falcosidekick` (2801), `falco-falcosidekick-ui` (2802).
- Alert log on node: `/var/log/falco/events.log` (hostPath mount inside the WSL2 VM, NOT the Windows repo).
- Rule names to assert: "Reverse Shell Tool in demoapp", "Shell Spawned by Web App in demoapp", "Read Sensitive File in demoapp", "Package Management in demoapp".
- Existing Makefile targets: `falco-install`, `phase-5` (from 05-01), `demo-3` (already runs reverse_shell.sh + privilege_probe.sh), `teardown-falco`.
</interfaces>

<research_corrections>
<!-- From 05-RESEARCH.md Pitfall 4 / Pitfall 6 / Validation Architecture -->
- Pitfall 4: hostPath `/var/log/falco` lives INSIDE the rancher-desktop WSL2 distro, not the Windows repo.
  Copy it out for viewing: `wsl -d rancher-desktop cat /var/log/falco/events.log > logs/falco.log`.
  Persistence (success criterion 5) is proven by the node hostPath surviving a pod restart; the repo
  copy is a convenience. `logs/falco.log` MUST be gitignored (runtime artifact).
- Pitfall 6: falcosidekick UI service is release-prefixed -> `falco-falcosidekick-ui`, not `falcosidekick-ui`.
- Success criterion 6: zero alerts during a normal Jenkins->ArgoCD cycle proves namespace scoping.
- ATK-01 has NO Falco detection rule: SQL injection executes within the Node.js process (string concat
  into a query), producing no detectable syscall/process-spawn. The verify script asserts `sqli.py exit 0`
  only (deterministic proof of data extraction) — it does NOT assert a Falco alert for ATK-01.
</research_corrections>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add logs/ persistence plumbing (logs/.gitkeep, .gitignore) and wire Makefile demo-3 + verify-phase-5</name>
  <files>logs/.gitkeep, .gitignore, Makefile</files>
  <read_first>
    - .gitignore (if it exists — otherwise create it)
    - Makefile (the `demo-3:` target ~line 232-238 and the `.PHONY` block near the top)
    - .planning/phases/05-runtime-security/05-RESEARCH.md ("Pitfall 4"; "Wave 0 Gaps")
  </read_first>
  <action>
    1. Create `logs/.gitkeep` (empty file) so the `logs/` directory is tracked.
    2. In `.gitignore` (create if missing) add these lines (do not remove existing entries):
       ```
       # Falco runtime alert log (copied out of the WSL2 VM at demo time)
       logs/falco.log
       ```
    3. In the Makefile `demo-3` target, ensure it runs ALL THREE attacks in order and copies the log out.
       Replace the current demo-3 recipe body with:
       ```
       demo-3:
       	@echo "── Demo Scenario 3: Live Attack Detected ────────────────────────────"
       	@python3 attacks/sqli.py || true
       	@bash attacks/reverse_shell.sh || true
       	@bash attacks/privilege_probe.sh || true
       	@echo ""
       	@echo "Copying Falco alert log out of the WSL2 VM..."
       	-@wsl -d rancher-desktop cat /var/log/falco/events.log > logs/falco.log 2>/dev/null || echo "  (run the copy-out manually on the target if wsl CLI is unavailable)"
       	@echo "Check Falco alerts:"
       	@echo "  Logs: kubectl logs -f -n falco -l app.kubernetes.io/name=falco"
       	@echo "  UI:   kubectl port-forward svc/falco-falcosidekick-ui -n falco 2802:2802  (then http://localhost:2802)"
       	@echo "  File: tail -20 logs/falco.log"
       ```
    4. Add a `verify-phase-5` target:
       ```
       verify-phase-5:
       	@bash falco/verify-phase5.sh
       ```
    5. Add `verify-phase-5` to the `.PHONY` list.
  </action>
  <verify>
    <automated>test -f logs/.gitkeep && grep -q "logs/falco.log" .gitignore && grep -q "^verify-phase-5:" Makefile && grep -q "python3 attacks/sqli.py" Makefile && grep -q "falco-falcosidekick-ui" Makefile && echo "plumbing OK"</automated>
  </verify>
  <acceptance_criteria>
    - `test -f logs/.gitkeep` succeeds
    - `grep -q "logs/falco.log" .gitignore` succeeds
    - `grep -q "^verify-phase-5:" Makefile` succeeds
    - demo-3 runs all three: `grep -q "python3 attacks/sqli.py" Makefile` AND `grep -q "attacks/reverse_shell.sh" Makefile` AND `grep -q "attacks/privilege_probe.sh" Makefile`
    - demo-3 copies out the log: `grep -q "wsl -d rancher-desktop cat /var/log/falco/events.log" Makefile`
    - UI service name correct: `grep -q "falco-falcosidekick-ui" Makefile`
  </acceptance_criteria>
  <done>logs/.gitkeep tracked, logs/falco.log gitignored, Makefile demo-3 runs all 3 attacks + copies the log out, verify-phase-5 target added.</done>
</task>

<task type="auto">
  <name>Task 2: Author falco/verify-phase5.sh (full phase-5 suite)</name>
  <files>falco/verify-phase5.sh</files>
  <read_first>
    - falco/verify-rules-loaded.sh (reuse its pod-resolution + log-grep helpers)
    - app/verify.sh (match ok/fail/info + PASS/FAIL counter convention)
    - attacks/sqli.py, attacks/reverse_shell.sh, attacks/privilege_probe.sh (the scripts this suite invokes)
    - .planning/phases/05-runtime-security/05-RESEARCH.md ("Validation Architecture" -> Phase Requirements -> Test Map, Sampling Rate)
  </read_first>
  <action>
    Create `falco/verify-phase5.sh` (bash, executable). Runs ON THE TARGET after `make phase-5`.
    Use the `RED/GREEN/YELLOW/NC` + `ok()/fail()/info()` + PASS/FAIL counter pattern from app/verify.sh.
    Steps (each an assertion; accumulate PASS/FAIL; exit 1 if any FAIL at the end):

    1. INSTALL/DRIVER (FALCO-01): call `bash falco/verify-rules-loaded.sh` and require exit 0
       (pod Running, modern_ebpf, 6 rule definitions, no parse errors). Fail the suite if it fails.
    2. WEBUI (FALCO-02): `kubectl get svc falco-falcosidekick-ui -n falco` succeeds (service exists).
    3. Define a helper `assert_alert_within_30s "<Rule Name>"` that:
       - records `START=$(date +%s)`, then loops up to 30s polling
         `kubectl logs -n falco -l app.kubernetes.io/name=falco --since=60s | grep -F "<Rule Name>"`;
       - `ok` if found within 30s, `fail` otherwise.
    4. ATK-01 (sqli): `python3 attacks/sqli.py` exits 0 (it is its own assertion). NO Falco alert is
       expected for ATK-01 — SQL injection runs inside the Node.js process, so there is no detectable
       syscall/spawn. Assert exit 0 ONLY; do NOT call assert_alert_within_30s for this attack.
    5. ATK-02 (reverse shell): `bash attacks/reverse_shell.sh`, then
       `assert_alert_within_30s "Shell Spawned by Web App in demoapp"` AND
       `assert_alert_within_30s "Reverse Shell Tool in demoapp"`.
    6. ATK-03 (privilege probe): `bash attacks/privilege_probe.sh`, then
       `assert_alert_within_30s "Read Sensitive File in demoapp"` AND
       `assert_alert_within_30s "Package Management in demoapp"`.
    7. PERSISTENCE (FALCO-02/success criterion 5): assert the node log is non-empty
       (`wsl -d rancher-desktop test -s /var/log/falco/events.log` on Windows; fall back to
       `kubectl exec` into the falco pod `test -s /var/log/falco/events.log`), then delete the falco
       pod (`kubectl delete pod -n falco -l app.kubernetes.io/name=falco`), wait for the new pod
       Running, and re-assert the log file STILL exists and is non-empty (survives restart).
    8. ZERO-ALERT-NORMAL-OPS (FALCO-04/success criterion 6): capture
       `kubectl logs -n falco -l app.kubernetes.io/name=falco --since=<phase-start>` and assert ZERO
       lines tagged `demo` originate from non-demoapp namespaces. Practical check: grep the log for
       `ns=kube-system|ns=argocd|ns=falco` on any `demo`-tagged alert and require zero matches.
       (Note in a comment: a full Jenkins->ArgoCD cycle should be run separately per success criterion 6;
       this step asserts no demo alerts leaked from system namespaces during the run.)
    9. Print final PASS/FAIL summary; `exit 1` if FAIL>0 else `exit 0`.

    Make executable (`chmod +x`).
  </action>
  <verify>
    <automated>bash -n falco/verify-phase5.sh && test -x falco/verify-phase5.sh && grep -q "verify-rules-loaded.sh" falco/verify-phase5.sh && grep -q "attacks/reverse_shell.sh" falco/verify-phase5.sh && grep -q "attacks/privilege_probe.sh" falco/verify-phase5.sh && grep -q "attacks/sqli.py" falco/verify-phase5.sh && grep -q "falco-falcosidekick-ui" falco/verify-phase5.sh && echo "verify-phase5.sh OK"</automated>
  </verify>
  <acceptance_criteria>
    - `bash -n falco/verify-phase5.sh` exits 0 AND `test -x falco/verify-phase5.sh`
    - Invokes the sub-verifier: `grep -q "verify-rules-loaded.sh" falco/verify-phase5.sh`
    - Invokes all 3 attacks: `grep -q "attacks/sqli.py"`, `grep -q "attacks/reverse_shell.sh"`, `grep -q "attacks/privilege_probe.sh"` all succeed
    - Asserts the 4 required rule names: `grep -q "Shell Spawned by Web App in demoapp"`, `grep -q "Reverse Shell Tool in demoapp"`, `grep -q "Read Sensitive File in demoapp"`, `grep -q "Package Management in demoapp"` all succeed
    - Has a 30s time-bound assertion: `grep -Eq "30|within" falco/verify-phase5.sh`
    - Persistence-after-restart present: `grep -q "delete pod" falco/verify-phase5.sh` AND `grep -q "/var/log/falco/events.log" falco/verify-phase5.sh`
    - Zero-alert scoping check present: `grep -Eq "kube-system|argocd" falco/verify-phase5.sh`
    - Correct UI service name: `grep -q "falco-falcosidekick-ui" falco/verify-phase5.sh`
  </acceptance_criteria>
  <done>falco/verify-phase5.sh valid+executable, chains rules-load check + 3 attacks + 30s alert assertions (ATK-02/ATK-03 only) + sqli exit-0 assertion (ATK-01, no alert) + persistence-after-restart + namespace-scope check, exits non-zero on any failure.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 3: Run Phase 5 end-to-end on the Windows/WSL2 target</name>
  <files>logs/falco.log (runtime, verified only)</files>
  <action>
    Human-run verification checkpoint (no code changes). The operator executes the numbered
    steps in <how-to-verify> below on the Windows/WSL2 Rancher Desktop target, in order, and
    reports the results. All commands are already automated by falco/verify-phase5.sh and the
    Makefile targets — this task confirms they pass on the real target (macOS is code-only, so
    the runtime proof cannot happen during authoring).
  </action>
  <what-built>
    Falco 0.44.1 values (modern_ebpf + json/file output + webui), 6 namespace-scoped custom rule
    definitions, three attack scripts, and a full verification suite (falco/verify-phase5.sh). Everything
    below is automated by the scripts — this checkpoint confirms it actually works on the real target, since
    all Phase 5 runtime execution happens on Windows/Rancher Desktop (macOS is code-only).
  </what-built>
  <how-to-verify>
    Run these on the Windows/WSL2 Rancher Desktop target, in order:

    1. DAY-1 BTF GATE (blocks the whole phase if it fails). In the node VM:
       `wsl -d rancher-desktop ls -l /sys/kernel/btf/vmlinux` (must exist) and
       `wsl -d rancher-desktop uname -r` (kernel >= 5.8).
       If missing: `wsl --update`, restart Rancher Desktop, re-check. No kmod fallback exists.
    2. VERIFY CLUSTERIP for the contact-k8s-api rule:
       `kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}'`.
       If it is NOT `10.43.0.1`, edit `falco/rules/custom-rules.yaml` + the customRules block in
       `falco/values.yaml` to the actual IP before installing (keep both in sync).
    3. INSTALL: `make phase-5` — wait for the Falco pod to reach Running (NOT CrashLoopBackOff):
       `kubectl get pods -n falco -w`.
    4. RULES LOADED: `bash falco/verify-rules-loaded.sh` — expect exit 0, "modern_ebpf"/"Falco initialized",
       all 6 rule names, zero parse errors.
    5. FULL SUITE: `make verify-phase-5` (runs falco/verify-phase5.sh). Expect a green PASS summary:
       sqli exit 0 (no alert expected); reverse-shell fires "Shell Spawned by Web App" + "Reverse Shell Tool"
       within 30s; privilege-probe fires "Read Sensitive File" + "Package Management" within 30s; the node
       events.log survives a Falco pod restart; zero demo alerts from kube-system/argocd/falco.
    6. WEBUI: `kubectl port-forward svc/falco-falcosidekick-ui -n falco 2802:2802` then open
       http://localhost:2802 — confirm >=3 distinct named alerts are visible.
    7. LOG COPY-OUT: `wsl -d rancher-desktop cat /var/log/falco/events.log > logs/falco.log` then
       `tail -20 logs/falco.log` — confirm JSON alert lines present.
    8. ZERO-ALERT-IN-NORMAL-OPS (success criterion 6): with `kubectl logs -f -n falco ...` tailing,
       run one full `make demo-2` (Jenkins -> ArgoCD) cycle and confirm NO demo-tagged Falco alerts appear.

    Report the PASS/FAIL summary from step 5, the count of distinct alerts in the webui (step 6),
    and whether step 8 produced zero alerts.
  </how-to-verify>
  <acceptance_criteria>
    - `/sys/kernel/btf/vmlinux` exists in the node VM and kernel >= 5.8
    - Falco pod is Running (no CrashLoopBackOff)
    - `bash falco/verify-rules-loaded.sh` exits 0
    - `make verify-phase-5` prints a green PASS summary (all assertions pass, exit 0)
    - Falcosidekick webui shows >= 3 distinct named alerts
    - `logs/falco.log` contains JSON alert lines after copy-out; events.log survived a pod restart
    - A full `make demo-2` cycle produces zero demo-tagged Falco alerts (namespace scoping confirmed)
  </acceptance_criteria>
  <resume-signal>Type "approved" with the verify-phase-5 summary + webui alert count, or describe the failures (e.g. BTF missing, a rule that did not fire, ClusterIP mismatch).</resume-signal>
</task>

</tasks>

<verification>
Authoring (macOS): Task 1 + Task 2 `<automated>` checks pass (files exist, bash -n clean, greps match).
Target (Windows/WSL2): Task 3 checkpoint — BTF gate, `make phase-5`, `make verify-phase-5` green,
webui >=3 alerts, log persists across restart, zero alerts during a normal pipeline cycle.
</verification>

<success_criteria>
- falco/verify-phase5.sh chains rules-load + 3 attacks + 30s assertions (ATK-02/ATK-03) + sqli exit-0 (ATK-01, no alert) + persistence + scope check
- logs/.gitkeep tracked; logs/falco.log gitignored; demo-3 runs all 3 attacks + copies log out; verify-phase-5 target present
- On target: Falco Running (modern_ebpf), 6 rules loaded, >=3 named alerts within 30s, log persists across pod restart, zero alerts in normal ops
</success_criteria>

<output>
After completion, create `.planning/phases/05-runtime-security/05-integration-verify-SUMMARY.md`
</output>
