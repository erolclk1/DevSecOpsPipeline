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
        demo-1 demo-2 demo-3 \
        registry-start registry-stop \
        argocd-install falco-install jenkins-start \
        reset-jenkins teardown-argocd teardown-falco

# ── Config ────────────────────────────────────────────────────────────────────
REGISTRY_PORT    := 5001
REGISTRY_HOST    := host.rancher-desktop.internal
ARGOCD_VERSION   := 10.1.0
FALCO_VERSION    := 9.1.0
JENKINS_IMAGE    := jenkins/jenkins:2.555.3-lts-jdk21
JENKINS_PORT     := 8080

# ── Top-level targets ─────────────────────────────────────────────────────────

## Bootstrap the full stack (all phases)
up: phase-1
	@echo ""
	@echo "✓ Phase 1 complete. Next phases (run in order):"
	@echo "  make phase-2         — build + scan + push demoapp"
	@echo "  make phase-2-deploy  — kubectl apply + rollout"
	@echo "  make verify-phase-2  — run Phase 2 success criteria checks"
	@echo "  make phase-3         — ArgoCD + Kyverno"
	@echo "  make phase-4         — Jenkins CI"
	@echo "  make phase-5         — Falco runtime security"

## Teardown everything
down: registry-stop teardown-argocd teardown-falco jenkins-stop
	@echo "✓ Stack torn down."

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

## Install ArgoCD v3.4.4
argocd-install:
	@echo "── Installing ArgoCD $(ARGOCD_VERSION) ──────────────────────────────"
	helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
	helm repo update argo
	helm upgrade --install argocd argo/argo-cd \
		--version $(ARGOCD_VERSION) \
		--namespace argocd --create-namespace \
		--set server.replicas=1 \
		--set controller.replicas=1 \
		--set redis-ha.enabled=false \
		--wait
	@echo "✓ ArgoCD installed"
	@echo "  Access UI: kubectl port-forward svc/argocd-server -n argocd 8443:443"
	@echo "  Password:  kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"

## Teardown ArgoCD
teardown-argocd:
	@helm uninstall argocd -n argocd 2>/dev/null && echo "✓ ArgoCD removed" || echo "  ArgoCD was not installed"
	@kubectl delete namespace argocd 2>/dev/null || true

# ── Phase 4: Jenkins CI ───────────────────────────────────────────────────────

## Start Jenkins with JCasC
jenkins-start:
	@echo "── Starting Jenkins ─────────────────────────────────────────────────"
	@if docker ps --format '{{.Names}}' | grep -q '^jenkins$$'; then \
		echo "✓ Jenkins already running at http://localhost:$(JENKINS_PORT)"; \
	else \
		docker rm -f jenkins 2>/dev/null || true; \
		docker run -d --name jenkins \
			-p $(JENKINS_PORT):8080 \
			-p 50000:50000 \
			-v jenkins_home:/var/jenkins_home \
			-v ~/.rd/docker.sock:/var/run/docker.sock \
			-e CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml \
			$(JENKINS_IMAGE); \
		echo "✓ Jenkins started at http://localhost:$(JENKINS_PORT)"; \
	fi

## Stop Jenkins
jenkins-stop:
	@docker rm -f jenkins 2>/dev/null && echo "✓ Jenkins stopped" || echo "  Jenkins was not running"

## Wipe Jenkins and reprovision from JCasC
reset-jenkins: jenkins-stop
	@docker volume rm jenkins_home 2>/dev/null || true
	@$(MAKE) jenkins-start
	@echo "✓ Jenkins reset — reprovision from JCasC"

# ── Phase 5: Falco ────────────────────────────────────────────────────────────

## Install Falco 0.44.1 with modern_ebpf
falco-install:
	@echo "── Installing Falco $(FALCO_VERSION) ────────────────────────────────"
	helm repo add falcosecurity https://falcosecurity.github.io/charts 2>/dev/null || true
	helm repo update falcosecurity
	helm upgrade --install falco falcosecurity/falco \
		--version $(FALCO_VERSION) \
		--namespace falco --create-namespace \
		--set driver.kind=modern_ebpf \
		--set tty=true \
		--set falcosidekick.enabled=true \
		--set falcosidekick.webui.enabled=true \
		--set collectors.kubernetes.enabled=true \
		--wait
	@echo "✓ Falco installed"
	@echo "  Logs:  kubectl logs -f -n falco -l app.kubernetes.io/name=falco"
	@echo "  UI:    kubectl port-forward svc/falco-falcosidekick-ui -n falco 2802:2802"

## Teardown Falco
teardown-falco:
	@helm uninstall falco -n falco 2>/dev/null && echo "✓ Falco removed" || echo "  Falco was not installed"
	@kubectl delete namespace falco 2>/dev/null || true

# ── Demo scenarios ────────────────────────────────────────────────────────────

## Demo 1: Blocked build — Trivy blocks vulnerable image
demo-1:
	@echo "── Demo Scenario 1: Blocked Build ───────────────────────────────────"
	@echo "Trigger a Jenkins build with the vulnerable Dockerfile."
	@echo "Expected: Trivy SCAN stage fails, image NOT pushed to registry."
	@echo ""
	@echo "Steps:"
	@echo "  1. Open Jenkins at http://localhost:$(JENKINS_PORT)"
	@echo "  2. Trigger pipeline on 'main' branch (uses vulnerable base image)"
	@echo "  3. Watch SCAN stage — should go red"
	@echo "  4. Confirm no new tag: curl http://$(REGISTRY_HOST):$(REGISTRY_PORT)/v2/demoapp/tags/list"

## Demo 2: Successful deploy — fixed image goes through full pipeline
demo-2:
	@echo "── Demo Scenario 2: Successful Deploy ───────────────────────────────"
	@echo "Trigger Jenkins build on 'fixed' branch."
	@echo "Expected: Trivy passes, ArgoCD syncs, pod updated."
	@echo ""
	@echo "Steps:"
	@echo "  1. Trigger Jenkins pipeline on 'fixed' branch"
	@echo "  2. Watch all 4 stages go green"
	@echo "  3. Check ArgoCD UI — Application syncs automatically"
	@echo "  4. Confirm new pod version: kubectl get pods -n demoapp"

## Demo 3: Live attack — Falco detects reverse shell and sensitive file access
demo-3:
	@echo "── Demo Scenario 3: Live Attack Detected ────────────────────────────"
	@bash attacks/reverse_shell.sh
	@bash attacks/privilege_probe.sh
	@echo ""
	@echo "Check Falco alerts:"
	@echo "  Logs: kubectl logs -f -n falco -l app.kubernetes.io/name=falco | jq ."
	@echo "  UI:   http://localhost:2802  (if port-forward is running)"
	@echo "  File: cat logs/falco.log | tail -20"
