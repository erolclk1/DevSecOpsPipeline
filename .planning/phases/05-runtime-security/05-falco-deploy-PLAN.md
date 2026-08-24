---
phase: 05-runtime-security
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - falco/values.yaml
  - falco/rules/custom-rules.yaml
  - falco/verify-rules-loaded.sh
  - Makefile
autonomous: true
requirements: [FALCO-01, FALCO-02, FALCO-03, FALCO-04, FALCO-05]

must_haves:
  truths:
    - "Falco installs with the modern_ebpf driver (never auto/kmod) and does not CrashLoop"
    - "Falco emits structured JSON alerts to kubectl logs in real time"
    - "Alerts persist to /var/log/falco/events.log on the node via Falco core file_output"
    - "5 custom rules load with zero parse errors"
    - "Every custom rule only matches the demoapp namespace/image (zero alerts from kube-system/argocd/falco)"
  artifacts:
    - path: "falco/values.yaml"
      provides: "Helm values: modern_ebpf driver, json+file output, hostPath mount, falcosidekick webui, inlined customRules"
      contains: "driver:"
    - path: "falco/rules/custom-rules.yaml"
      provides: "5 namespace-scoped detection rules + in_demoapp macro (source of truth)"
      contains: "in_demoapp"
    - path: "falco/verify-rules-loaded.sh"
      provides: "Wave 0 test: greps Falco startup logs for the 5 rule names + zero parse errors"
  key_links:
    - from: "falco/values.yaml"
      to: "falco/rules/custom-rules.yaml"
      via: "customRules['custom-rules.yaml'] inlines the rules file content"
      pattern: "customRules:"
    - from: "Makefile falco-install"
      to: "falco/values.yaml"
      via: "helm install -f falco/values.yaml"
      pattern: "\\-f falco/values.yaml"
---

<objective>
Author the Falco 0.44.1 deployment configuration and the 5 namespace-scoped custom
detection rules for the demoapp container, plus a fast rules-load verification script.

Purpose: This plan produces the runtime-detection control layer (the third thesis
security layer). Correct chart keys and driver pinning here are what make the live
attack demo (Plan 05-03) reproducible.
Output: falco/values.yaml, falco/rules/custom-rules.yaml, falco/verify-rules-loaded.sh,
and an updated Makefile falco-install target that installs from the values file.

NOTE: All authoring happens on macOS (code only). The actual `helm install` and log
assertions run on the Windows/WSL2 Rancher Desktop target — see Plan 05-03.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/05-runtime-security/05-RESEARCH.md
@CLAUDE.md
@deploy/base/namespace.yaml
@deploy/base/service.yaml
@app/Dockerfile

<interfaces>
<!-- Confirmed environment facts the executor must build against (no exploration needed). -->
- Namespace: `demoapp` (deploy/base/namespace.yaml)
- Container name: `demoapp`; image repo suffix `/demoapp` (image `host.rancher-desktop.internal:5001/demoapp:<sha>`)
- Service: NodePort 30080 -> containerPort 3000 (deploy/base/service.yaml)
- App base image: `node:14.21.3-alpine` -> busybox (NO bash, NO /dev/tcp, busybox `nc` has no `-e`)
- Falco chart: `falcosecurity/falco` version `9.1.0` (appVersion 0.44.1). Do NOT upgrade.
- Falcosidekick services after `helm install falco ...`: `falco-falcosidekick` (2801), `falco-falcosidekick-ui` (2802)
- Existing Makefile `falco-install` target currently uses `--set` chains — this plan replaces it with a values-file install.
</interfaces>

<research_corrections>
<!-- CRITICAL from 05-RESEARCH.md — the ROADMAP text is factually wrong on these points. -->
1. Falcosidekick has NO file sink. Persistence uses Falco CORE `file_output`, not Falcosidekick.
2. Volume keys are `mounts.volumes` / `mounts.volumeMounts` (NOT `extraVolumes`/`extraVolumeMounts`).
3. `falco.json_output` defaults to FALSE — must set `true` for FALCO-05.
4. Falcosidekick webui key is `falcosidekick.webui.enabled` (NOT `webui.create`).
5. Do NOT add `fd.sip != "127.0.0.1"` to the reverse-shell rule — the demo targets loopback, so that exclusion would suppress the alert. Detect on PROCESS SPAWN instead.
6. `k8s.ns.name` works without the k8smeta collector; layer `container.image.repository endswith "/demoapp"` for robustness.
</research_corrections>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Author falco/values.yaml (driver, json+file output, hostPath, webui) and update Makefile falco-install</name>
  <files>falco/values.yaml, Makefile</files>
  <read_first>
    - falco/values.yaml (if it exists — otherwise you are creating it)
    - .planning/phases/05-runtime-security/05-RESEARCH.md (sections "Code Examples" -> Helm install, "Pattern 1", "Pattern 3")
    - Makefile (the existing `falco-install:` target ~lines 197-212, plus the `.PHONY` block near the top)
    - CLAUDE.md (Critical Rule 2: driver.kind=modern_ebpf; Rule 3: registry hostname)
  </read_first>
  <action>
    Create `falco/values.yaml` with EXACTLY these keys (chart 9.1.0, verified in RESEARCH.md):

    ```yaml
    # Source: falcosecurity/charts falco-9.1.0/values.yaml (verified 2026-08-24)
    driver:
      kind: modern_ebpf          # FALCO-01: explicit, NEVER auto (no kmod fallback on RD VM)
    tty: true                    # FALCO-05: live flush so `kubectl logs -f` shows alerts immediately

    falco:
      json_output: true          # FALCO-05: structured JSON (chart default is false)
      file_output:               # FALCO-02: persistence via Falco CORE (Falcosidekick has no file sink)
        enabled: true
        keep_alive: false
        filename: /var/log/falco/events.log
      # falco.rules_files default already includes /etc/falco/rules.d (where customRules mount)

    mounts:                       # NOT extraVolumes/extraVolumeMounts — chart uses mounts.*
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
        enabled: true            # optional (adds k8smeta pod + ghcr dependency); keep true for richer metadata

    falcosidekick:
      enabled: true
      webui:
        enabled: true            # FALCO-02: key is webui.enabled (NOT webui.create)

    customRules:
      custom-rules.yaml: |-
        # PLACEHOLDER — Task 2 inlines the exact content of falco/rules/custom-rules.yaml here.
        # Keep 2-space indentation under this block scalar.
    ```

    Then update the Makefile `falco-install` target (currently ~line 197-212) to install from the
    values file instead of `--set` chains. Replace the `helm upgrade --install falco ...` command with:

    ```
    helm upgrade --install falco falcosecurity/falco \
    	--version $(FALCO_VERSION) \
    	--namespace falco --create-namespace \
    	-f falco/values.yaml \
    	--wait
    ```

    Keep the existing `helm repo add`/`helm repo update` lines and the trailing echo lines.
    Add a `phase-5` target (alias) adjacent to `falco-install`:

    ```
    phase-5: falco-install
    ```

    Add `phase-5` to the `.PHONY` list at the top of the Makefile.
    Do NOT change any other Makefile target.
  </action>
  <verify>
    <automated>python3 -c "import yaml; d=yaml.safe_load(open('falco/values.yaml')); assert d['driver']['kind']=='modern_ebpf'; assert d['falco']['json_output'] is True; assert d['falco']['file_output']['enabled'] is True; assert d['falco']['file_output']['filename']=='/var/log/falco/events.log'; assert d['mounts']['volumes'][0]['hostPath']['path']=='/var/log/falco'; assert d['falcosidekick']['webui']['enabled'] is True; assert 'custom-rules.yaml' in d['customRules']; print('values.yaml OK')" && grep -q "\-f falco/values.yaml" Makefile && grep -q "^phase-5:" Makefile && ! grep -q "\-\-set driver.kind" Makefile && echo "Makefile OK"</automated>
  </verify>
  <acceptance_criteria>
    - `grep -q "kind: modern_ebpf" falco/values.yaml` succeeds
    - `grep -q "json_output: true" falco/values.yaml` succeeds
    - `grep -q "filename: /var/log/falco/events.log" falco/values.yaml` succeeds
    - `grep -A3 "^mounts:" falco/values.yaml | grep -q "volumes:"` succeeds (proves mounts.volumes, NOT extraVolumes)
    - `grep -q "customRules:" falco/values.yaml` succeeds
    - `grep -q "\-f falco/values.yaml" Makefile` succeeds AND `! grep -q "\-\-set driver.kind" Makefile` (old --set chains removed)
    - `grep -q "^phase-5:" Makefile` succeeds
    - `! grep -Eq "webui.create|extraVolumes|kind: auto" falco/values.yaml` (none of the wrong keys present)
  </acceptance_criteria>
  <done>falco/values.yaml exists with all corrected chart keys, and Makefile falco-install installs from it via `-f falco/values.yaml`; `make phase-5` target present.</done>
</task>

<task type="auto">
  <name>Task 2: Author the 5 namespace-scoped custom rules and inline them into values.yaml</name>
  <files>falco/rules/custom-rules.yaml, falco/values.yaml</files>
  <read_first>
    - falco/rules/custom-rules.yaml (if it exists — otherwise you are creating it)
    - falco/values.yaml (created in Task 1 — you will replace the customRules placeholder)
    - .planning/phases/05-runtime-security/05-RESEARCH.md (section "Code Examples" -> custom-rules.yaml; "Anti-Patterns"; "Pitfall 3")
    - app/server.js (confirms /cmd -> child_process.exec -> /bin/sh -c; /sqli string concat)
  </read_first>
  <action>
    Create `falco/rules/custom-rules.yaml` as the human-editable SOURCE OF TRUTH with EXACTLY
    these lists + macro + 5 rules (from RESEARCH.md Code Examples; firing validated on target in Plan 05-03):

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

    # 1a. reverse-shell: network tool spawned (fires on execve; no socket connection needed)
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

    # 5. contact-k8s-api  (verify ClusterIP on target: kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}')
    - macro: demo_outbound
      condition: (evt.type = connect and evt.dir = < and fd.type in (ipv4))
    - rule: Contact K8s API Server from demoapp
      desc: demoapp pod connected to the Kubernetes API server
      condition: demo_outbound and in_demoapp and (fd.sip = "10.43.0.1" or fd.sport in (443, 6443))
      output: "demoapp contacted K8s API (conn=%fd.name proc=%proc.cmdline ns=%k8s.ns.name)"
      priority: NOTICE
      tags: [demo, T1613]
    ```

    Then open `falco/values.yaml` and REPLACE the `customRules['custom-rules.yaml']` placeholder
    block scalar with the FULL content above, re-indented to sit under the `|-` block scalar
    (i.e. every line indented 4 spaces relative to `customRules:`). The block scalar text must be
    byte-for-byte the rules file content (just re-indented). Keep the two files in sync — the
    standalone file is the source of truth; the values.yaml copy is what the chart mounts to
    `/etc/falco/rules.d`.

    Do NOT add any `fd.sip != "127.0.0.1"` exclusion (Pitfall 3). Do NOT edit `falco_rules.yaml`.
  </action>
  <verify>
    <automated>python3 -c "import yaml; docs=list(yaml.safe_load_all(open('falco/rules/custom-rules.yaml'))); print('parsed docs ok')" && test $(grep -c "^- rule:" falco/rules/custom-rules.yaml) -eq 5 && python3 -c "import yaml; v=yaml.safe_load(open('falco/values.yaml')); c=v['customRules']['custom-rules.yaml']; assert c.count('- rule:')==5, c.count('- rule:'); assert 'in_demoapp' in c; print('values customRules has 5 rules, in sync')"</automated>
  </verify>
  <acceptance_criteria>
    - `test $(grep -c "^- rule:" falco/rules/custom-rules.yaml) -eq 5` (exactly 5 rules)
    - `grep -q "in_demoapp" falco/rules/custom-rules.yaml` and each rule condition contains `in_demoapp` (FALCO-04 scoping): `test $(grep -c "and in_demoapp\|demo_outbound and in_demoapp" falco/rules/custom-rules.yaml) -ge 5`
    - Rule names present: `grep -q "Reverse Shell Tool in demoapp"`, `grep -q "Shell Spawned by Web App in demoapp"`, `grep -q "Read Sensitive File in demoapp"`, `grep -q "Package Management in demoapp"`, `grep -q "Contact K8s API Server from demoapp"` all succeed
    - `! grep -q '127.0.0.1' falco/rules/custom-rules.yaml` (no loopback exclusion — Pitfall 3)
    - Python assertion confirms values.yaml customRules block contains exactly 5 rules and `in_demoapp` (files in sync)
  </acceptance_criteria>
  <done>falco/rules/custom-rules.yaml has 5 namespace-scoped rules; identical content inlined under customRules in values.yaml; no loopback exclusion.</done>
</task>

<task type="auto">
  <name>Task 3: Author falco/verify-rules-loaded.sh (Wave 0 rules-load test)</name>
  <files>falco/verify-rules-loaded.sh</files>
  <read_first>
    - app/verify.sh (match the ok/fail/info color-helper convention + PASS/FAIL counters)
    - falco/rules/custom-rules.yaml (source of the 5 rule names to assert)
    - .planning/phases/05-runtime-security/05-RESEARCH.md (section "Validation Architecture" -> Wave 0 Gaps; Testing Strategy commands)
  </read_first>
  <action>
    Create `falco/verify-rules-loaded.sh` (bash, executable). It runs ON THE TARGET after
    `make phase-5`. It must:

    1. Resolve the Falco pod: `POD=$(kubectl get pod -n falco -l app.kubernetes.io/name=falco -o jsonpath='{.items[0].metadata.name}')`. Fail if empty.
    2. Assert the pod is Running (not CrashLoopBackOff): `kubectl get pod -n falco "$POD" -o jsonpath='{.status.phase}'` equals `Running`.
    3. Capture startup logs once: `LOGS=$(kubectl logs -n falco "$POD" 2>&1)`.
    4. Assert driver: `echo "$LOGS" | grep -Eq "modern_ebpf|Falco initialized"` (FALCO-01).
    5. Assert ZERO parse errors: `echo "$LOGS" | grep -Eiq "unknown macro|unknown list|Error|rule .* has an invalid"` must be FALSE (fail if any match).
    6. Assert all 5 rule names appear as loaded. Falco logs each loaded rule; grep the log for each of the 5 exact rule names (define them in a bash array): "Reverse Shell Tool in demoapp", "Stdio to Network in demoapp", "Shell Spawned by Web App in demoapp", "Read Sensitive File in demoapp", "Package Management in demoapp", "Contact K8s API Server from demoapp". (That is 6 rule strings — 1a/1b both count; assert at least the 5 requirement rules by name; missing any is a fail.)
    7. Print a PASS/FAIL summary and `exit 1` if any check failed, `exit 0` if all pass.

    Use the same `RED/GREEN/YELLOW/NC` + `ok()/fail()/info()` helpers as app/verify.sh.
    Add a header comment: "Run on the Windows/WSL2 target after `make phase-5`."
    Make it executable (`chmod +x`).
  </action>
  <verify>
    <automated>bash -n falco/verify-rules-loaded.sh && test -x falco/verify-rules-loaded.sh && grep -q "app.kubernetes.io/name=falco" falco/verify-rules-loaded.sh && grep -q "modern_ebpf" falco/verify-rules-loaded.sh && echo "verify-rules-loaded.sh syntax OK"</automated>
  </verify>
  <acceptance_criteria>
    - `bash -n falco/verify-rules-loaded.sh` exits 0 (valid bash syntax)
    - `test -x falco/verify-rules-loaded.sh` (executable bit set)
    - `grep -q "modern_ebpf" falco/verify-rules-loaded.sh` (driver assertion present)
    - `grep -Eq "unknown macro|Error" falco/verify-rules-loaded.sh` (parse-error assertion present)
    - All 5 rule-name strings present: `grep -q "Reverse Shell Tool in demoapp"`, `grep -q "Shell Spawned by Web App in demoapp"`, `grep -q "Read Sensitive File in demoapp"`, `grep -q "Package Management in demoapp"`, `grep -q "Contact K8s API Server from demoapp"` all succeed
    - Script contains `exit 1` on failure path and `exit 0` on success path
  </acceptance_criteria>
  <done>falco/verify-rules-loaded.sh is valid, executable, asserts pod Running + modern_ebpf + zero parse errors + all 5 rule names loaded.</done>
</task>

</tasks>

<verification>
On macOS (authoring), all three tasks pass their `<automated>` checks:
- `python3 -c "import yaml; ..."` validates values.yaml keys and rule sync
- `grep -c "^- rule:" falco/rules/custom-rules.yaml` == 5
- `bash -n falco/verify-rules-loaded.sh` clean

On the Windows/WSL2 target (deferred to Plan 05-03): `make phase-5` then
`bash falco/verify-rules-loaded.sh` exits 0.
</verification>

<success_criteria>
- falco/values.yaml pins driver.kind=modern_ebpf, json_output+file_output on, mounts.volumes hostPath, falcosidekick.webui.enabled, customRules inlined
- falco/rules/custom-rules.yaml has exactly 5 rules, all scoped with in_demoapp, no loopback exclusion
- Makefile falco-install installs from `-f falco/values.yaml`; `make phase-5` alias exists
- falco/verify-rules-loaded.sh valid + executable, asserts driver + zero parse errors + 5 rule names
</success_criteria>

<output>
After completion, create `.planning/phases/05-runtime-security/05-falco-deploy-SUMMARY.md`
</output>
