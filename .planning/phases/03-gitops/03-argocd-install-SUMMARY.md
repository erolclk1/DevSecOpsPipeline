---
plan: "03-01"
title: "ArgoCD Install + Application CR + Self-Heal Verification"
status: complete
completed: 2026-08-12
---

## What Was Built

ArgoCD v3.4.4 running in `argocd` namespace (non-HA, single-node), Application CR wired to the GitHub repo, initial sync confirmed Synced/Healthy, self-heal demonstration passed.

## Key Files Created

- `bootstrap/argocd/argocd-install.sh` — Helm install script (non-HA, dex disabled, resource limits, 30s sync interval)
- `bootstrap/argocd/application.yaml` — Application CR watching `deploy/overlays/local/`, selfHeal + prune, ignoreDifferences pre-configured for Kyverno
- `bootstrap/argocd/apply.sh` — applies Application CR and waits for Synced/Healthy
- `bootstrap/argocd/verify.sh` — 4 automated success criteria checks

## Phase 3 ArgoCD Success Criteria

| SC | Check | Result |
|----|-------|--------|
| SC1 | ArgoCD Application demoapp Synced + Healthy | PASS |
| SC2 | demoapp pod running image from local registry | PASS |
| SC3 | bootstrap/argocd/application.yaml committed | PASS |
| SC4 | Helm chart argo-cd-10.1.0 deployed | PASS |

## Self-Heal Demo (GITOPS-05)

- `kubectl edit deployment demoapp -n demoapp` — changed image tag to `WRONGTAG`
- ArgoCD reverted to correct tag within 30 seconds
- ArgoCD UI showed `OutOfSync → Syncing → Synced` cycle

## Self-Check: PASSED
