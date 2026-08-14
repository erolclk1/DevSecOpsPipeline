---
phase: 4
slug: jenkins-ci
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-14
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell scripts (curl, docker, kubectl) — no unit test framework |
| **Config file** | none — pipeline is the test harness |
| **Quick run command** | `curl -s http://localhost:8080/api/json \| jq .` (Jenkins health) |
| **Full suite command** | `bash ci/jenkins-reset.sh && make demo-1 && make demo-2` |
| **Estimated runtime** | ~10–20 minutes (full pipeline run) |

---

## Sampling Rate

- **After every task commit:** Run quick run command (Jenkins up + responding)
- **After every plan wave:** Run smoke test for that wave's deliverables
- **Before `/gsd:verify-work`:** Full pipeline (demo-1 + demo-2) must pass
- **Max feedback latency:** 120 seconds for quick check; 20 min for full suite

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 4-01-01 | 01 | 1 | CI-01 | integration | `docker compose -f ci/docker-compose.yml up -d && curl -s http://localhost:8080/login` | ❌ W0 | ⬜ pending |
| 4-01-02 | 01 | 1 | CI-02 | integration | `docker exec jenkins cat /var/jenkins_home/casc_configs/jenkins.yaml` | ❌ W0 | ⬜ pending |
| 4-01-03 | 01 | 1 | CI-03 | integration | `docker exec jenkins jenkins-plugin-cli --list \| grep configuration-as-code` | ❌ W0 | ⬜ pending |
| 4-02-01 | 02 | 2 | CI-04 | integration | `docker exec jenkins cat /proc/1/environ \| tr '\0' '\n' \| grep TRIVY` | ❌ W0 | ⬜ pending |
| 4-02-02 | 02 | 2 | CI-05 | integration | `# Trigger build with vulnerable image, confirm SCAN stage fails` | manual | See Manual-Only | ❌ W0 | ⬜ pending |
| 4-02-03 | 02 | 2 | CI-06 | integration | `curl http://localhost:5001/v2/demoapp/tags/list` (no new tag after SCAN fail) | ❌ W0 | ⬜ pending |
| 4-02-04 | 02 | 2 | CI-07 | manual | `ls ci/jenkins-reset.sh && bash ci/jenkins-reset.sh` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `ci/smoke-test.sh` — curl-based health checks for Jenkins + registry
- [ ] `ci/verify-pipeline.sh` — runs demo-1 (fail) and demo-2 (pass) and checks outcomes

*Existing app/ and deploy/ infrastructure covers Phase 1–3 verification; Phase 4 adds pipeline smoke scripts.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Jenkins boots with JCasC, no setup wizard | CI-01 | Requires browser/UI check that setup wizard is bypassed | Navigate to http://localhost:8080 — must land on dashboard, not wizard |
| SCAN stage shows Trivy CVE table in build log | CI-04 | Log content inspection | Open Jenkins build log for a failing build; confirm Trivy CVE output visible |
| SBOM archived as build artefact | CI-05 | Jenkins artefact UI | Open passing build → Artefacts → verify `sbom.cdx.json` present |
| ArgoCD syncs new pod after BUMP | CI-06 | Requires ArgoCD + cluster observation | After green build, watch `kubectl get pods -n demoapp -w` and ArgoCD UI |
| `jenkins-reset.sh` produces same config | CI-07 | Full teardown + reprovision | Run reset, wait for Jenkins to start, verify same seed job and credentials present |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s (quick) / 20min (full)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
