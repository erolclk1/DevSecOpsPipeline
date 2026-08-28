---
phase: 05-runtime-security
plan: 05-falco-deploy
subsystem: infra
tags: [falco, helm, ebpf, kubernetes, runtime-security, custom-rules]

requires:
  - phase: 04-jenkins-ci
    provides: working cluster with demoapp deployed in demoapp namespace

provides:
  - falco/values.yaml — Helm values for Falco 0.44.1 with modern_ebpf, json_output, file_output, Falcosidekick webui
  - falco/rules/custom-rules.yaml — 6 namespace-scoped Falco detection rules (demoapp only)
  - falco/verify-rules-loaded.sh — smoke test: pod Running, driver modern_ebpf, 6 rules loaded

affects: [05-integration-verify, Phase 6 demo polish]

tech-stack:
  added: [falco 0.44.1, falcosecurity/falco helm chart 9.1.0, falcosidekick, modern_ebpf]
  patterns: [custom Falco rules via customRules values key, in_demoapp macro for namespace scoping, Falco core file_output for persistence]

key-files:
  created:
    - falco/values.yaml
    - falco/rules/custom-rules.yaml
    - falco/verify-rules-loaded.sh

key-decisions:
  - "Falcosidekick has no file output — persistence uses Falco core file_output (falco.file_output.enabled=true)"
  - "Volume keys are mounts.volumes / mounts.volumeMounts (not extraVolumes)"
  - "6 rule definitions cover 5 FALCO-03 requirements: reverse-shell = rule 1a (Reverse Shell Tool) + 1b (Stdio to Network)"
  - "All rules use in_demoapp macro: k8s.ns.name = demoapp AND container.image.repository endswith /demoapp"
  - "Reverse-shell detection on process spawn (not fd.sip) — fires regardless of socket connect success"

patterns-established:
  - "in_demoapp macro: scope all custom rules to prevent false positives in argocd/kube-system/falco namespaces"
  - "customRules values key: inline YAML in values.yaml, loaded into /etc/falco/rules.d by chart"
  - "Falco core file_output to hostPath /var/log/falco/ + mounts.volumes for persistence"

requirements-completed: [FALCO-01, FALCO-02, FALCO-03, FALCO-04, FALCO-05]

duration: ~25min
completed: 2026-08-28
---

# Phase 05 Plan falco-deploy Summary

**Falco 0.44.1 deployment config: values.yaml with modern_ebpf + json/file output + 6 namespace-scoped detection rules + rules-load smoke test.**

## Accomplishments

- `falco/values.yaml`: Helm values pinning `driver.kind=modern_ebpf`, `falco.json_output=true`, `falco.file_output.enabled=true` to `/var/log/falco/falco.log`, `falcosidekick.enabled=true`, `falcosidekick.webui.enabled=true`, `mounts.volumes` hostPath for persistence, `customRules` inline block
- `falco/rules/custom-rules.yaml`: 6 detection rules all gated by `in_demoapp` macro (k8s.ns.name=demoapp + container.image.repository):
  1. Reverse Shell Tool in demoapp (detects nc/mkfifo on process spawn)
  2. Stdio to Network in demoapp (detects fd.type=ipv4 piped to sh)
  3. Shell Spawned by Web App in demoapp (detects sh/bash child of node/python)
  4. Read Sensitive File in demoapp (/etc/shadow, /etc/sudoers, .ssh/*)
  5. Package Management in demoapp (apk/apt/pip at runtime)
  6. Contact K8s API Server from demoapp (app hitting kubernetes.default.svc)
- `falco/verify-rules-loaded.sh`: smoke test asserting pod Running, driver modern_ebpf, zero parse errors, all 6 rule names in startup logs

## Issues / Deviations

- Research correction applied: `falco.file_output` used for persistence (not Falcosidekick — it has no file sink)
- Research correction applied: `mounts.volumes` used (not `extraVolumes`)
- 6 rules created to fulfill 5 FALCO-03 requirements (reverse-shell split into 1a + 1b for busybox-safe detection)
