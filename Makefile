# Makefile — DevSecOps Pipeline (Cybersecurity Thesis)
#
# PREREQUISITE (manual, one-time):
#   Install Rancher Desktop 1.23.1 from https://github.com/rancher-sandbox/rancher-desktop/releases/tag/v1.23.1
#   Set Memory to 6 GB in Preferences → Resources
#   Wait for "Kubernetes: Running" before running any make target.
#
# USAGE:
#   make up          — full bootstrap (all phases)
#   make phase-1     — Phase 1: registry + cluster
#   make demo-1      — Demo scenario 1: blocked build
#   make demo-2      — Demo scenario 2: successful deploy
#   make demo-3      — Demo scenario 3: live attack detected
#   make down        — teardown everything
#   make status      — show current stack status

SHELL := /bin/bash
.PHONY: up down status phase-1 verify-phase-1 \
        phase-2 phase-2-deploy verify-phase-2 \
        phase-3 phase-3-apply verify-phase-3-argocd \
        phase-3-kyverno verify-phase-3-kyverno \
        argocd-install kyverno-install \
        demo-1 demo-2 demo-3 \
        registry-start registry-stop \
        falco-install phase-5 phase-4 jenkins-stop \
        reset-jenkins verify-jenkins verify-phase-4 verify-phase-5 \
        teardown-argocd teardown-falco teardown-kyverno stack demo-warmup

# ── Config ────────────────────────────────────────────────────────────────────
REGISTRY_PORT    := 5001
REGISTRY_HOST    := host.rancher-desktop.internal
FALCO_VERSION    := 9.1.0
JENKINS_IMAGE    := jenkins/jenkins:2.555.3-lts-jdk21
JENKINS_PORT     := 8080

# ── Top-level targets ─────────────────────────────────────────────────────────

## Bootstrap the full stack (all phases)
up: phase-1
	@echo ""
	@echo "══════════════════════════════════════════════════════════════"
	@echo "  ACTION REQUIRED: Restart Rancher Desktop to apply"
	@echo "  the registry config written to ~/.rd/k3s/registries.yaml"
	@echo ""
	@echo "  Run:  rdctl shutdown && rdctl start"
	@echo "  Wait: ~60 s for Kubernetes: Running in the RD tray icon"
	@echo "  Then: make stack"
	@echo "══════════════════════════════════════════════════════════════"

## Teardown everything
down: registry-stop teardown-argocd teardown-falco jenkins-stop
	@echo "✓ Stack torn down."

## Bootstrap full stack after Rancher Desktop restart (installs ArgoCD, Kyverno, Jenkins, Falco)
stack: phase-3 phase-3-apply phase-3-kyverno phase-4 phase-5
	@echo ""
	@echo "✓ Full stack bootstrapped."
	@echo "  Run: make demo-warmup   — warms Trivy DB + verifies components before demo"
	@echo "  Run: make demo-1 / demo-2 / demo-3"

## Show stack status
status:
	@echo "── Cluster ──────────────────────────────────────────────────────────"
	@kubectl get nodes --no-headers 2>/dev/null || echo "  k3s: not running"
	@echo "── Registry ─────────────────────────────────────────────────────────"
	@docker ps --filter name=registry --format "  {{.Names}}: {{.Status}}" 2>/dev/null || echo "  registry: not running"
	@echo "── ArgoCD ───────────────────────────────────────────────────────────"
	@kubectl get pods -n argocd --no-headers 2>/dev/null | awk '{print "  "$$1": "$$3}' || echo "  argocd: not installed"
	@echo "── Falco ────────────────────────────────────────────────────────────"
	@kubectl get pods -n falco --no-headers 2>/dev/null | awk '{print "  "$$1": "$$3}' || echo "  falco: not installed"
	@echo "── Jenkins ──────────────────────────────────────────────────────────"
	@docker ps --filter name=jenkins --format "  {{.Names}}: {{.Status}}" 2>/dev/null || echo "  jenkins: not running"

# ── Phase 1: Bootstrap ────────────────────────────────────────────────────────

## Phase 1: registry:2 + registries.yaml + k3s verification
phase-1: registry-start configure-registry
	@echo ""
	@echo "Rancher Desktop must be restarted to load the new registry config."
	@echo "Run: rdctl shutdown && rdctl start"
	@echo "Then run: make verify-phase-1"

## Copy registries.yaml and prompt for RD restart
configure-registry:
	@echo "── Configuring k3s registry mirror ─────────────────────────────────"
	@mkdir -p ~/.rd/k3s/
	@cp cluster/registries.yaml ~/.rd/k3s/registries.yaml
	@echo "✓ Copied cluster/registries.yaml → ~/.rd/k3s/registries.yaml"

## Start the local Docker registry
registry-start:
	@echo "── Starting local registry ──────────────────────────────────────────"
	@if docker ps --format '{{.Names}}' | grep -q '^registry$$'; then \
		echo "✓ registry:2 already running"; \
	else \
		docker rm -f registry 2>/dev/null || true; \
		docker run -d --restart=always -p $(REGISTRY_PORT):5000 --name registry registry:2; \
		echo "✓ registry:2 started on port $(REGISTRY_PORT)"; \
	fi
	@curl -sf http://localhost:$(REGISTRY_PORT)/v2/ | grep -q '{}' && \
		echo "✓ Registry reachable at localhost:$(REGISTRY_PORT)" || \
		echo "✗ Registry not reachable — check docker ps"

## Stop the local Docker registry
registry-stop:
	@docker rm -f registry 2>/dev/null && echo "✓ Registry stopped" || echo "  Registry was not running"

## Verify Phase 1 success criteria
verify-phase-1:
	@bash cluster/verify.sh

# ── Phase 2: Vulnerable App ───────────────────────────────────────────────────

## Phase 2: build + Trivy scan + push demoapp image
phase-2:
	@bash app/build.sh

## Phase 2: update overlay tag + kubectl apply + rollout
phase-2-deploy:
	@bash app/deploy.sh

## Run Phase 2 success criteria checks
verify-phase-2:
	@bash app/verify.sh

# ── Phase 3: GitOps ───────────────────────────────────────────────────────────

# ── Phase 3: GitOps (ArgoCD + Kyverno) ───────────────────────────────────────

## Phase 3: install ArgoCD (helm install + sync interval config)
phase-3:
	@bash bootstrap/argocd/argocd-install.sh

## Phase 3: apply ArgoCD Application CR and wait for Synced/Healthy
phase-3-apply:
	@bash bootstrap/argocd/apply.sh

## Run Phase 3 ArgoCD success criteria checks
verify-phase-3-argocd:
	@bash bootstrap/argocd/verify.sh

## Phase 3: install Kyverno + apply 4 ClusterPolicies
phase-3-kyverno:
	@bash bootstrap/kyverno/kyverno-install.sh

## Run Phase 3 Kyverno success criteria checks
verify-phase-3-kyverno:
	@bash bootstrap/kyverno/verify.sh

## Install ArgoCD v3.4.4 (non-HA, dex disabled, resource limits, 30s sync)
argocd-install:
	@bash bootstrap/argocd/argocd-install.sh

## Install Kyverno v1.18.2 with 4 ClusterPolicies
kyverno-install:
	@bash bootstrap/kyverno/kyverno-install.sh

## Teardown ArgoCD
teardown-argocd:
	@helm uninstall argocd -n argocd 2>/dev/null && echo "✓ ArgoCD removed" || echo "  ArgoCD was not installed"
	@kubectl delete namespace argocd 2>/dev/null || true

## Teardown Kyverno
teardown-kyverno:
	@kubectl delete -f bootstrap/kyverno/ 2>/dev/null || true
	@helm uninstall kyverno -n kyverno 2>/dev/null && echo "✓ Kyverno removed" || echo "  Kyverno was not installed"
	@kubectl delete namespace kyverno 2>/dev/null || true

# ── Phase 4: Jenkins CI ───────────────────────────────────────────────────────

## Phase 4: build + start Jenkins (controller + agent) from docker-compose + JCasC
phase-4:
	@docker compose -f ci/docker-compose.yml up -d --build
	@echo "✓ Jenkins starting at http://localhost:$(JENKINS_PORT) (JCasC, no wizard)"
	@echo "  Waiting for Jenkins to boot (~60s)..."
	@sleep 10
	@bash ci/smoke-test.sh

## Quick Jenkins health + JCasC parity check
verify-jenkins:
	@bash ci/smoke-test.sh
	@bash ci/tests/verify-jcasc.sh

## Run all Phase 4 success criteria (smoke + JCasC + both scenarios)
verify-phase-4:
	@echo "── Phase 4 Verification ─────────────────────────────────────────────"
	@bash ci/smoke-test.sh
	@bash ci/tests/verify-jcasc.sh
	@bash ci/tests/scenario-1.sh
	@bash ci/tests/scenario-2.sh
	@echo ""
	@echo "✓ Phase 4 verification complete"

## Stop Jenkins (keep volumes)
jenkins-stop:
	@docker compose -f ci/docker-compose.yml down 2>/dev/null && echo "✓ Jenkins stopped" || echo "  Jenkins was not running"

## Wipe Jenkins volumes and reprovision from JCasC
reset-jenkins:
	@bash ci/jenkins-reset.sh

# ── Phase 5: Falco ────────────────────────────────────────────────────────────
phase-5:
	@mkdir -p logs
	@echo "── Phase 5: Runtime Security ────────────────────────────────────────"
	@echo ""
	@echo "Step 1/4: BTF pre-check (modern_ebpf requires /sys/kernel/btf/vmlinux)"
	@wsl -d rancher-desktop -- sh -c "if test -f /sys/kernel/btf/vmlinux; then echo BTF_OK; else echo BTF_MISSING; exit 1; fi"
	@echo ""
	@echo "Step 2/4: Install Falco 0.44.1 (modern_ebpf)"
	@$(MAKE) falco-install
	@echo ""
	@echo "Step 3/4: Full verification suite (rules-load + 3 attacks + 30s alert assertions)"
	@bash falco/verify-phase5.sh
	@echo ""
	@echo "Step 4/4: Copy Falco alert log out of WSL2 VM"
	-@wsl -d rancher-desktop -- sh -c "cat /var/log/falco/events.log" > logs/falco.log 2>/dev/null && \
		echo "✓ logs/falco.log updated ($$(wc -l < logs/falco.log) lines)" || \
		echo "  (wsl copy-out unavailable — log is in /var/log/falco/events.log inside the VM)"
	@echo ""
	@echo "✓ Phase 5 complete — Falco detecting attacks in real time"
	@echo "  WebUI: kubectl port-forward svc/falco-falcosidekick-ui -n falco 2802:2802"
	@echo "  Logs:  kubectl logs -f -n falco -l app.kubernetes.io/name=falco"
	@echo "  File:  tail -20 logs/falco.log"

## Install Falco 0.44.1 with modern_ebpf
falco-install:
	@echo "── Installing Falco $(FALCO_VERSION) ────────────────────────────────"
	helm repo add falcosecurity https://falcosecurity.github.io/charts 2>/dev/null || true
	helm repo update falcosecurity
	helm upgrade --install falco falcosecurity/falco \
		--version $(FALCO_VERSION) \
		--namespace falco --create-namespace \
		-f falco/values.yaml \
		--wait
	@echo "✓ Falco installed"
	@echo "  Logs:  kubectl logs -f -n falco -l app.kubernetes.io/name=falco"
	@echo "  UI:    kubectl port-forward svc/falco-falcosidekick-ui -n falco 2802:2802"

## Teardown Falco
teardown-falco:
	@helm uninstall falco -n falco 2>/dev/null && echo "✓ Falco removed" || echo "  Falco was not installed"
	@kubectl delete namespace falco 2>/dev/null || true

# ── Demo scenarios ────────────────────────────────────────────────────────────

## Demo 1: Blocked build — Trivy blocks vulnerable image (automated)
demo-1:
	@echo "── Demo Scenario 1: Blocked Build ───────────────────────────────────"
	@bash ci/tests/scenario-1.sh

## Demo 2: Successful deploy — fixed image goes through full pipeline (automated)
demo-2:
	@echo "── Demo Scenario 2: Successful Deploy ───────────────────────────────"
	@bash ci/tests/scenario-2.sh

## Demo 3: Live attack — Falco detects reverse shell and sensitive file access
demo-3:
	@echo "── Demo Scenario 3: Live Attack Detected ────────────────────────────"
	@python3 attacks/sqli.py || true
	@bash attacks/reverse_shell.sh || true
	@bash attacks/privilege_probe.sh || true
	@echo ""
	@echo "Copying Falco alert log out of the WSL2 VM..."
	-@wsl -d rancher-desktop cat /var/log/falco/events.log > logs/falco.log 2>/dev/null || echo "  (run the copy-out manually on the target if wsl CLI is unavailable)"
	@echo "Check Falco alerts:"
	@echo "  Logs: kubectl logs -f -n falco -l app.kubernetes.io/name=falco"
	@echo "  UI:   kubectl port-forward svc/falco-falcosidekick-ui -n falco 2802:2802  (then http://localhost:2802)"
	@echo "  File: tail -20 logs/falco.log"

## Run Phase 5 end-to-end verification (requires Falco running + demoapp deployed)
verify-phase-5:
	@bash falco/verify-phase5.sh
