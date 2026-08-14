---
phase: 04-jenkins-ci
plan: 04
type: execute
wave: 4
depends_on: ["04-03"]
files_modified: []
autonomous: false
requirements: [CI-01, CI-02, CI-03, CI-04, CI-05, CI-06, CI-07]
must_haves:
  truths:
    - "Jenkins boots from JCasC to a dashboard (not the setup wizard)"
    - "A vulnerable build turns the SCAN stage red and pushes no new registry tag"
    - "A fixed build goes green across all four stages, pushes a SHA tag, bumps the manifest, and ArgoCD deploys it"
    - "The CycloneDX SBOM is present as a build artefact"
    - "jenkins-reset.sh reproduces the fully configured instance with no UI steps"
  artifacts: []
  key_links:
    - from: "Jenkins BUMP commit on main"
      to: "ArgoCD-managed demoapp pod"
      via: "ArgoCD auto-sync of deploy/overlays/local"
      pattern: "demoapp"
---

<objective>
Phase gate: run both demo scenarios end-to-end against the live stack and confirm the human-observable behaviors that automated greps cannot — the Jenkins dashboard (no wizard), the red SCAN stage, the ArgoCD sync of the fixed image, the SBOM artefact in the build UI, and a clean reset reproduction.

Purpose: Proves the whole Phase 4 pipeline works as a demonstration, not just that files contain the right strings. This is the gate before `/gsd:verify-work`.
Output: Human sign-off (no files changed).
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
</execution_context>

<context>
@.planning/ROADMAP.md
@.planning/phases/04-jenkins-ci/04-VALIDATION.md
@.planning/phases/04-jenkins-ci/04-RESEARCH.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Bring up the stack and run both scenario scripts</name>
  <files>(none — runs scripts, changes no files)</files>
  <read_first>
    - ci/tests/scenario-1.sh (blocked-build assertions)
    - ci/tests/scenario-2.sh (successful-deploy assertions)
    - ci/smoke-test.sh (health check)
    - ci/tests/verify-jcasc.sh (plugin parity + no-wizard)
  </read_first>
  <action>
    On the Windows/WSL2 target with Rancher Desktop running and `ci/.env` populated (copied from `ci/.env.example`, real GITHUB_TOKEN + admin creds), automate as much as possible before the human checkpoint:
    1. `make phase-4` (or `bash ci/jenkins-reset.sh`) to build + start controller and agent.
    2. `bash ci/smoke-test.sh` — must exit 0 (Jenkins on 8080, agent reaches docker socket). If it fails on the agent docker check, the socket mount path is wrong (RESEARCH Pitfall 1) — try the alternate path and note it.
    3. `bash ci/tests/verify-jcasc.sh` — must exit 0 (no wizard, plugin parity, demoapp-pipeline present).
    4. `bash ci/tests/scenario-1.sh` — vulnerable build blocks at SCAN, no new registry tag.
    5. `bash ci/tests/scenario-2.sh` — fixed build green, SHA tag in registry, manifest bumped on main.
    6. Watch ArgoCD adopt the bump: `kubectl get pods -n demoapp -w` until the pod image matches the new SHA (do NOT `kubectl apply` — ArgoCD must do it).
    Collect the outputs to present at the checkpoint.
  </action>
  <verify>
    <automated>bash ci/smoke-test.sh && bash ci/tests/verify-jcasc.sh && bash ci/tests/scenario-1.sh && bash ci/tests/scenario-2.sh</automated>
  </verify>
  <acceptance_criteria>
    - `bash ci/smoke-test.sh` exits 0
    - `bash ci/tests/verify-jcasc.sh` exits 0
    - `bash ci/tests/scenario-1.sh` exits 0 (block confirmed)
    - `bash ci/tests/scenario-2.sh` exits 0 (deploy confirmed)
    - `curl -sf http://localhost:5001/v2/demoapp/tags/list` includes the current git short SHA after Scenario 2
  </acceptance_criteria>
  <done>All four scripts exit 0 and the demoapp pod is running the newly built SHA via ArgoCD.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Checkpoint: Human verification of both demo scenarios</name>
  <action>Present the collected script outputs from Task 1, then walk the human through the five verification steps in how-to-verify below (dashboard-not-wizard, red SCAN + no tag, green 4 stages + SBOM artefact, ArgoCD-synced pod on new SHA, reset reproduction). Do not proceed until the human responds.</action>
  <what-built>
    A JCasC-provisioned Jenkins (controller + docker-builder agent) running the 4-stage
    demoapp-pipeline: BUILD (SHA tag) -> SCAN (Trivy gate) -> PUSH -> BUMP (yq + git push [skip ci]),
    with CycloneDX SBOM archived per run. Two scenario scripts exercised the blocked and the
    successful paths; ArgoCD deployed the fixed image.
  </what-built>
  <how-to-verify>
    1. Open http://localhost:8080 — you must land on the Jenkins DASHBOARD, not a setup wizard
       or "Unlock Jenkins" screen (CI-01). The `demoapp-pipeline` job is listed.
    2. Open the Scenario 1 (vulnerable) build -> Stage View: the SCAN stage is RED and the pipeline
       stopped there. Open its console log: a Trivy CVE table for HIGH/CRITICAL is visible (CI-03).
       Confirm the registry shows no new tag:
       `curl http://host.rancher-desktop.internal:5001/v2/demoapp/tags/list`
    3. Open the Scenario 2 (fixed) build -> Stage View: all four stages BUILD/SCAN/PUSH/BUMP are GREEN.
       Open Artifacts -> `demoapp-sbom.json` is present and downloadable (CI-06).
    4. Confirm the GitOps deploy: `git log origin/main -1 --oneline -- deploy/overlays/local/demoapp-patch.yaml`
       shows the `ci: bump demoapp to <sha> [skip ci]` commit (CI-05), and `kubectl get pods -n demoapp -o wide`
       plus the ArgoCD UI show the demoapp pod running the new SHA — with NO manual kubectl apply.
    5. Reproducibility (CI-07): run `bash ci/jenkins-reset.sh`, wait for boot, reopen http://localhost:8080 —
       the `demoapp-pipeline` job, the github-token credential, and the docker-builder node all reappear
       with no UI configuration.
  </how-to-verify>
  <resume-signal>Type "approved" if all five checks pass, or describe which check failed (e.g., "SCAN stage green on vulnerable build", "wizard appeared", "ArgoCD did not sync").</resume-signal>
</task>

</tasks>

<verification>
- All four automated scripts exit 0 (smoke, verify-jcasc, scenario-1, scenario-2).
- Human confirms: dashboard not wizard; red SCAN + no tag on vulnerable; green 4 stages + SBOM artefact on fixed; ArgoCD-synced pod on the new SHA; reset reproduces config.
</verification>

<success_criteria>
- Phase 4 success criteria 1-5 from ROADMAP.md all observed live.
- No `kubectl apply` was run by the operator to deploy the fixed image (ArgoCD did it).
- Ready for `/gsd:verify-work` and phase transition.
</success_criteria>

<output>
After completion, create `.planning/phases/04-jenkins-ci/04-scenario-verification-SUMMARY.md`.
</output>
