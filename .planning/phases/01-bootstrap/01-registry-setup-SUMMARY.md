---
plan: "01-01"
title: "Rancher Desktop + Registry Setup"
status: complete
completed: 2026-07-20
target_machine: "Windows + Rancher Desktop 1.23.1 (dockerd/moby engine, WSL2 backend)"
dev_machine: "macOS (code authoring / Claude Code only — pipeline does NOT run here)"
---

## What Was Built

Infrastructure-as-code artefacts for Phase 1 bootstrap — registry:2 on host port 5001, and the provisioning script that makes dockerd inside the Rancher Desktop VM trust it over HTTP on every restart.

**Target machine:** Windows + Rancher Desktop 1.23.1, container engine = **dockerd (moby)**.

## Key Files Created

- `cluster/registries.yaml` — containerd mirror config (kept for reference; NOT used when engine is dockerd)
- `cluster/insecure-registry.start` — **THE working fix**: RD provisioning script that writes `insecure-registries` into `/etc/docker/daemon.json` inside the VM on every boot
- `cluster/install-provisioning.sh` — copies `insecure-registry.start` to `%LOCALAPPDATA%\rancher-desktop\provisioning\` with correct LF line endings
- `cluster/setup.sh` — starts `registry:2` on port 5001, calls `install-provisioning.sh`
- `cluster/verify.sh` — checks all 4 success criteria
- `Makefile` — phase targets

## Requirements Addressed

- INFRA-01: `registry:2` started via `make phase-1` / `cluster/setup.sh` on port 5001
- INFRA-02: provisioning script committed — ensures insecure-registries config survives RD restarts

## Root Cause Discovered

**`registries.yaml` is ignored when using the dockerd engine.**

Rancher Desktop with the **dockerd (moby)** engine routes k8s image pulls through `cri-dockerd` → the Docker daemon. This means `/etc/rancher/k3s/registries.yaml` (containerd-only config) is **completely bypassed**. The daemon defaults to HTTPS and rejects the HTTP registry:

```
http: server gave HTTP response to HTTPS client
```

The fix is `insecure-registries: ["host.rancher-desktop.internal:5001"]` in `/etc/docker/daemon.json` **inside the VM**. A manually written `daemon.json` is overwritten by RD on every restart — so the durable solution is a **provisioning script** at:

```
%LOCALAPPDATA%\rancher-desktop\provisioning\insecure-registry.start
```

RD executes it inside the VM on every start, before dockerd — so the config is always applied.

## Decisions Made

- Registry port 5001 (not 5000 — RD occupies 5000 internally)
- Push from host via `localhost:5001` (HTTP, no TLS issue)
- Pod image refs use `host.rancher-desktop.internal:5001` (resolved inside VM)
- Provisioning script MUST have LF line endings — `install-provisioning.sh` strips CR via `tr -d '\r'`

## Self-Check: PASSED

All Wave 1 artefacts committed and tested on Windows + Rancher Desktop (dockerd engine).
