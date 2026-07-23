---
plan: "01-02"
title: "End-to-End Pull Verification"
status: complete
completed: 2026-07-20
---

## What Was Built

Verified end-to-end registry pull path on Windows + Rancher Desktop 1.23.1 (dockerd/moby engine).

## Verification Results

All 4 Phase 1 success criteria passed on target machine (Windows + Rancher Desktop):

- SC1: `kubectl get nodes` → Ready ✓
- SC2: `curl http://localhost:5001/v2/` → `{}` ✓
- SC3: Pod `pull-test` reached Succeeded — image pulled from `host.rancher-desktop.internal:5001` ✓
- SC4: In-cluster curl → `{}` — registry reachable from inside k3s cluster ✓

## Requirements Addressed

- INFRA-03: `kubectl get nodes` Ready + registry reachable from inside cluster

## Key Decisions & Root-Cause Fixes

1. **Registry port is 5001, not 5000** — Rancher Desktop occupies port 5000 internally. `registry:2` published on host `5001:5000`.

2. **Two hostnames, two purposes:**
   - `docker push` uses `localhost:5001` (localhost is always treated as HTTP by Docker — no TLS negotiation)
   - Pod image refs use `host.rancher-desktop.internal:5001` (k8s resolves this into the VM)
   - Both point at the same registry; only the hostname differs.

3. **THE root-cause fix — dockerd engine ignores registries.yaml:**
   Rancher Desktop with the **dockerd (moby)** engine pulls k8s images through `cri-dockerd` → the Docker daemon, NOT containerd. Therefore `/etc/rancher/k3s/registries.yaml` (containerd-only) is **completely ignored**. The daemon defaulted to HTTPS and rejected the HTTP registry with:
   `http: server gave HTTP response to HTTPS client`.

   The fix is `insecure-registries` in the Docker daemon config **inside the VM**. A manually-written `/etc/docker/daemon.json` is **overwritten by RD on every restart**, so the durable solution is a **provisioning script**.

4. **Provisioning script is restart-proof:**
   `cluster/insecure-registry.start` is installed to `%LOCALAPPDATA%\rancher-desktop\provisioning\` (via `cluster/install-provisioning.sh`). RD runs it inside the VM on every start, BEFORE dockerd — so `daemon.json` with `insecure-registries: ["host.rancher-desktop.internal:5001"]` is re-applied on every boot. Confirmed via `docker info | grep -A2 'Insecure Registries'`.
   Provisioning scripts MUST have Unix (LF) line endings — the installer strips CR.

## Files (final Phase 1 artefacts)

- `cluster/registries.yaml` — containerd mirror config (kept for the containerd-engine path; unused with dockerd)
- `cluster/insecure-registry.start` — RD provisioning script (THE working fix for dockerd engine)
- `cluster/install-provisioning.sh` — installs the provisioning script with LF endings
- `cluster/setup.sh` — starts registry:2 on 5001, installs provisioning script
- `cluster/verify.sh` — checks all 4 success criteria (push via localhost, pull via cluster hostname)
- `Makefile` — phase targets

## Self-Check: PASSED

Phase 1 complete. All INFRA-01, INFRA-02, INFRA-03 requirements verified on Windows + Rancher Desktop (dockerd engine).
