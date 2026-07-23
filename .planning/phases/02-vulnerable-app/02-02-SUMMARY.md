---
plan: "02-02"
title: "Build, Push, Deploy, and Acceptance Verify"
status: complete
completed: 2026-07-23
target_machine: "Windows + Rancher Desktop 1.23.1 (WSL2 backend)"
image_tag: "6af2848"
nodeport: 30080
---

## What Was Built

Running `demoapp` pod in `demoapp` namespace, accessible on NodePort 30080, with all four Phase 2 success criteria verified.

## Key Files Created

- `deploy/base/namespace.yaml` — demoapp namespace
- `deploy/base/deployment.yaml` — Deployment with readinessProbe, resource limits, no USER directive (runs as root)
- `deploy/base/service.yaml` — NodePort 30080
- `deploy/base/kustomization.yaml` — Kustomize base
- `deploy/overlays/local/demoapp-patch.yaml` — image patch (current tag: `6af2848`)
- `deploy/overlays/local/kustomization.yaml` — overlay wiring base + patch
- `app/build.sh` — build + Trivy scan + push (splits HOST_REGISTRY=localhost vs CLUSTER_REGISTRY=host.rancher-desktop.internal)
- `app/deploy.sh` — patches overlay tag + kubectl apply + rollout wait
- `app/verify.sh` — runs all 4 success criteria checks

## Phase 2 Success Criteria

| SC | Check | Result |
|----|-------|--------|
| SC1 | `trivy image --severity HIGH,CRITICAL --exit-code 1` exits non-zero with CRITICAL CVEs | PASS |
| SC2 | `kubectl exec <pod> -n demoapp -- whoami` returns `root` | PASS |
| SC3 | `/sqli?user=' OR '1'='1` returns SQL error containing injected query string | PASS |
| SC4 | `/cmd?input=id` returns `uid=0(root)` in stdout | PASS |

## Requirements Addressed

- APP-01: `/sqli` endpoint with string-concatenated SQL query confirmed exploitable
- APP-02: `/cmd` endpoint with `child_process.exec` confirmed exploitable
- APP-03: `node:14.21.3-alpine` base image — Trivy reports CRITICAL CVEs on every scan
- APP-04: Container runs as root (no USER directive) — confirmed via `whoami`

## Decisions Made

- `build.sh` uses two separate variables: `HOST_REGISTRY=localhost:5001` for docker push (host-side), `CLUSTER_REGISTRY=host.rancher-desktop.internal:5001` for the deploy overlay (cluster-side). This split was necessary because `host.rancher-desktop.internal` does not resolve from the Windows host, only from inside the k3s VM.
- Port 5001 confirmed as the working registry port (5000 conflicted with Rancher Desktop's internal proxy).
- `daemon.json` `insecure-registries` entry (applied via provisioning script in Phase 1 fixup) is required — `registries.yaml` alone is not sufficient for the dockerd engine.

## Self-Check: PASSED

All four success criteria confirmed on target machine. Phase 2 complete.
