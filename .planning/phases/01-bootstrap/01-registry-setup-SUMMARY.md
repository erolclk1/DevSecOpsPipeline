---
plan: "01-01"
title: "Rancher Desktop + Registry Setup"
status: complete
completed: 2026-07-03
---

## What Was Built

Infrastructure-as-code artefacts for Phase 1 bootstrap — everything needed to set up the registry and k3s cluster on any machine with Rancher Desktop installed.

## Key Files Created

- `cluster/registries.yaml` — containerd mirror config for k3s; tells Rancher Desktop to pull from `host.rancher-desktop.internal:5000` over HTTP with TLS skipped
- `cluster/setup.sh` — bootstrap script: starts `registry:2`, copies `registries.yaml` to `~/.rd/k3s/`, prompts for RD restart
- `cluster/verify.sh` — Phase 1 success criteria checker: verifies all 4 SC (node Ready, host curl, pod pull, in-cluster curl)
- `Makefile` — top-level automation: `make phase-1`, `make verify-phase-1`, `make argocd-install`, `make falco-install`, `make demo-{1,2,3}`, `make status`, `make down`

## Requirements Addressed

- INFRA-01: registry:2 started via `make phase-1` / `cluster/setup.sh`
- INFRA-02: `cluster/registries.yaml` committed with exact mirror syntax for Rancher Desktop 1.23.1

## Decisions Made

- Registry hostname `host.rancher-desktop.internal:5000` used everywhere (never localhost in manifests, never hardcoded IP)
- Docker socket path for Rancher Desktop: `~/.rd/docker.sock` (documented in Makefile jenkins-start target)
- Makefile grows with each phase — Phase 3/4/5 targets already scaffolded

## Self-Check: PASSED

All Wave 1 artefacts committed. Wave 2 (pull-verification) requires a live Rancher Desktop instance — pending human verification on target machine.
