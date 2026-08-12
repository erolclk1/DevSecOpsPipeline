---
plan: "03-02"
title: "Kyverno Install + 4 Policies + Admission Blocking Demo"
status: complete
completed: 2026-08-12
---

## What Was Built

Kyverno v1.18.2 (chart 3.8.2) running in `kyverno` namespace, 4 ClusterPolicies applied, admission blocking confirmed for `:latest` tags, PolicyReport populated, ArgoCD sync loop did not occur.

## Key Files Created

- `bootstrap/kyverno/kyverno-install.sh` — Helm install + 60s webhook wait + policy apply + background controller restart
- `bootstrap/kyverno/disallow-latest-tag.yaml` — Enforce mode, blocks `:latest` and untagged images
- `bootstrap/kyverno/restrict-image-registries.yaml` — Audit mode, scoped to `demoapp` namespace only
- `bootstrap/kyverno/disallow-privileged-containers.yaml` — Audit mode, cluster-wide
- `bootstrap/kyverno/require-resource-limits.yaml` — Audit mode, cluster-wide
- `bootstrap/kyverno/verify.sh` — 6 automated success criteria checks

## Phase 3 Kyverno Success Criteria

| SC | Check | Result |
|----|-------|--------|
| SC1 | All 4 ClusterPolicies present | PASS |
| SC2 | disallow-latest-tag in Enforce mode | PASS |
| SC3 | restrict-image-registries scoped to demoapp namespace | PASS |
| SC4 | `:latest` image blocked at admission | PASS |
| SC5 | PolicyReport populated in demoapp namespace | PASS |
| SC6 | ArgoCD still Synced+Healthy after Kyverno install | PASS |

## Decisions Made

- No sync loop occurred — the `ignoreDifferences.managedFieldsManagers` pre-configured in the Application CR was sufficient
- `restrict-image-registries` kept in Audit mode (not Enforce) to avoid blocking system pod pulls from external registries
- `disallow-privileged-containers` kept in Audit mode to allow Falco DaemonSet in Phase 5 (uses privileged mode)

## Self-Check: PASSED
