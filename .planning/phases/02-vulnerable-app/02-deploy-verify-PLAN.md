---
id: "02-02"
title: "Build, Push, Deploy, and Acceptance Verify"
wave: 2
depends_on: ["02-01"]
requirements_addressed: [APP-01, APP-02, APP-03, APP-04]
files_modified:
  - deploy/base/namespace.yaml
  - deploy/base/deployment.yaml
  - deploy/base/service.yaml
  - deploy/base/kustomization.yaml
  - deploy/overlays/local/kustomization.yaml
  - deploy/overlays/local/demoapp-patch.yaml
autonomous: false
must_haves:
  truths:
    - "trivy image --severity HIGH,CRITICAL --exit-code 1 host.rancher-desktop.internal:5000/demoapp:<tag> exits non-zero with at least one CRITICAL CVE"
    - "kubectl exec <pod> -n demoapp -- whoami returns root"
    - "curl /sqli?user=' OR '1'='1 returns a response proving SQL injection is possible (DB error or data leak, not a clean 500)"
    - "curl /cmd?input=id returns the container user identity in the response body"
  artifacts:
    - path: "deploy/base/deployment.yaml"
      provides: "Kustomize base deployment manifest for demoapp"
      contains: "demoapp"
    - path: "deploy/base/service.yaml"
      provides: "NodePort service for host access during manual deploy phase"
      contains: "NodePort"
    - path: "deploy/overlays/local/demoapp-patch.yaml"
      provides: "Image tag patch — the single line CI will update in Phase 4"
      contains: "host.rancher-desktop.internal:5000/demoapp"
  key_links:
    - from: "deploy/overlays/local/"
      to: "ArgoCD Application path (Phase 3)"
      via: "Kustomize overlay — ArgoCD will watch this exact path"
      pattern: "demoapp-patch.yaml image tag = git short SHA"
---

<objective>
On the **Windows target machine**: pull the app artefacts from Git, build and push the Docker image to the local registry, write the Kustomize manifests, deploy with raw `kubectl apply`, and run the four acceptance tests that prove all Phase 2 success criteria are met.

Purpose: This is the manual deploy path that must work before ArgoCD is introduced in Phase 3. It also validates the vulnerability design — each attack vector must be exercisable from the host before adding pipeline automation.

Output: Running `demoapp` pod in `demoapp` namespace, accessible from the host on a NodePort, with all four success criteria verified.
</objective>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@CLAUDE.md
@cluster/registries.yaml
</context>

<tasks>

<task id="1" title="Build and push the demoapp image to the local registry">
<read_first>
- cluster/registries.yaml — confirms the registry hostname (host.rancher-desktop.internal:5000)
- CLAUDE.md — Critical Rules: image tags must be git short SHA, never :latest; registry is host.rancher-desktop.internal:5000
- .planning/phases/01-bootstrap/01-pull-verification-SUMMARY.md — confirms host.rancher-desktop.internal resolves correctly on Windows RD
</read_first>
<action>
**All commands in this task run on the Windows target machine (Git Bash or WSL2 terminal).**

1. Pull the latest code from Git (includes the `app/` artefacts committed in Plan 02-01):
   ```
   git pull origin main
   ```

2. Determine the image tag (git short SHA — never :latest):
   ```
   export TAG=$(git rev-parse --short HEAD)
   echo "Image tag: $TAG"
   ```

3. Build the Docker image:
   ```
   cd app/
   docker build -t host.rancher-desktop.internal:5000/demoapp:${TAG} .
   ```
   Expected output: `Successfully built <image-id>` and `Successfully tagged host.rancher-desktop.internal:5000/demoapp:<TAG>`.

   If the build fails at `npm install` (e.g. package-lock.json missing), run:
   ```
   docker build --no-cache -t host.rancher-desktop.internal:5000/demoapp:${TAG} .
   ```

4. Run Trivy scan to confirm CRITICAL CVEs exist (Phase 2 SC1):
   ```
   trivy image \
     --severity HIGH,CRITICAL \
     --exit-code 1 \
     host.rancher-desktop.internal:5000/demoapp:${TAG}
   ```
   Expected: Trivy exits non-zero and reports at least one CRITICAL CVE.
   If Trivy exits 0 with 0 findings, the base image is wrong OR the Trivy DB is stale — do NOT continue. Diagnose:
   - Confirm `docker inspect host.rancher-desktop.internal:5000/demoapp:${TAG} | grep -i "node:14"` shows the expected base.
   - Run `trivy image --download-db-only` to refresh the DB and re-scan.

5. Push the image to the local registry:
   ```
   docker push host.rancher-desktop.internal:5000/demoapp:${TAG}
   ```
   Verify the push succeeded:
   ```
   curl http://host.rancher-desktop.internal:5000/v2/demoapp/tags/list
   ```
   Expected: `{"name":"demoapp","tags":["<TAG>"]}`

6. Return to the repo root and export the tag for use in the next task:
   ```
   cd ..
   echo "TAG=${TAG}" > .env.phase2
   ```
   (This file is only used locally during Phase 2 — it is gitignored.)
</action>
<acceptance_criteria>
- `docker build` exits 0 and the image `host.rancher-desktop.internal:5000/demoapp:<TAG>` exists locally
- `trivy image --severity HIGH,CRITICAL --exit-code 1 host.rancher-desktop.internal:5000/demoapp:<TAG>` exits non-zero with at least one CRITICAL CVE in the output
- `curl http://host.rancher-desktop.internal:5000/v2/demoapp/tags/list` returns `{"name":"demoapp","tags":["<TAG>"]}`
- `docker push` exited 0 — the image is in the registry, not just local
</acceptance_criteria>
</task>

<task id="2" title="Write Kustomize base manifests and the local overlay">
<read_first>
- CLAUDE.md — architecture section: deploy/base/ = Kustomize base; deploy/overlays/local/ = ArgoCD watches this path only
- .planning/ROADMAP.md — Phase 2 task 4: Namespace, Deployment (image placeholder), Service (NodePort); Phase 2 task 5: demoapp-patch.yaml with initial image tag
- .planning/ROADMAP.md — Phase 3 task 3: "tag change is exactly one line in demoapp-patch.yaml" — the overlay structure must already be set up this way
</read_first>
<action>
**This task authors manifests on the macOS dev machine (code authoring). The `apply` step in Task 3 runs on Windows.**

Create the following directory structure and files:

```
deploy/
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    └── local/
        ├── kustomization.yaml
        └── demoapp-patch.yaml
```

**`deploy/base/namespace.yaml`**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: demoapp
```

**`deploy/base/deployment.yaml`**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demoapp
  namespace: demoapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demoapp
  template:
    metadata:
      labels:
        app: demoapp
    spec:
      containers:
        - name: demoapp
          image: demoapp:placeholder
          ports:
            - containerPort: 3000
          readinessProbe:
            httpGet:
              path: /
              port: 3000
            initialDelaySeconds: 15
            periodSeconds: 10
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
          env:
            - name: PORT
              value: "3000"
```

Notes on the deployment:
- `image: demoapp:placeholder` — the overlay patch replaces this with the full registry path + SHA tag.
- `initialDelaySeconds: 15` on the readiness probe — prevents ArgoCD from marking the app Degraded during slow startup (addresses ROADMAP Phase 3 Pitfall 9).
- `resources.limits` are set — required by the Kyverno `require-resource-limits` policy in Phase 3.
- No `securityContext.runAsUser` — the container runs as root (APP-04 requirement; Kyverno will flag this as a policy violation in Phase 3).

**`deploy/base/service.yaml`**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: demoapp
  namespace: demoapp
spec:
  type: NodePort
  selector:
    app: demoapp
  ports:
    - protocol: TCP
      port: 3000
      targetPort: 3000
      nodePort: 30080
```

NodePort 30080 is used consistently through all phases so all runbooks use the same port. If 30080 is already in use on the target machine, use 30081 and update `docs/` references accordingly.

**`deploy/base/kustomization.yaml`**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
```

**`deploy/overlays/local/demoapp-patch.yaml`**

Replace `<TAG>` with the actual git short SHA from Task 1 (check `.env.phase2` or run `git rev-parse --short HEAD`):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demoapp
  namespace: demoapp
spec:
  template:
    spec:
      containers:
        - name: demoapp
          image: host.rancher-desktop.internal:5000/demoapp:<TAG>
```

This is the **single line** that CI (Phase 4) will update via `yq`. The entire GitOps demonstration turns on this one file being the canonical source of truth for the deployed image version.

**`deploy/overlays/local/kustomization.yaml`**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

patches:
  - path: demoapp-patch.yaml
    target:
      kind: Deployment
      name: demoapp
```

After authoring, stage and commit:
```
git add deploy/
git commit -m "feat(02-vulnerable-app): add Kustomize base manifests and local overlay"
```

Then push to origin so the Windows machine can pull:
```
git push origin main
```
</action>
<acceptance_criteria>
- `deploy/base/kustomization.yaml`, `namespace.yaml`, `deployment.yaml`, `service.yaml` all exist
- `deploy/overlays/local/kustomization.yaml` and `demoapp-patch.yaml` both exist
- `deploy/base/deployment.yaml` does NOT have a `securityContext.runAsUser` directive (runs as root)
- `deploy/base/deployment.yaml` has `readinessProbe.initialDelaySeconds: 15`
- `deploy/base/deployment.yaml` has `resources.limits` defined
- `deploy/overlays/local/demoapp-patch.yaml` contains `host.rancher-desktop.internal:5000/demoapp:<TAG>` (the real tag from Task 1)
- `git log --oneline -1` shows the manifest commit
</acceptance_criteria>
</task>

<task id="3" title="Deploy with kubectl apply and run the four acceptance tests">
<read_first>
- deploy/overlays/local/demoapp-patch.yaml — confirm it contains the correct image tag before applying
- CLAUDE.md — Jenkins MUST NOT kubectl apply (rule 1); this manual apply is the Phase 2 exception — Phase 3 hands this over to ArgoCD
- cluster/registries.yaml — registry reachable (confirmed in Phase 1)
</read_first>
<action>
**All commands in this task run on the Windows target machine (Git Bash or WSL2).**

1. Pull the latest manifests from Git:
   ```
   git pull origin main
   ```

2. Deploy using `kubectl apply -k`:
   ```
   kubectl apply -k deploy/overlays/local/
   ```
   Expected output:
   ```
   namespace/demoapp created
   deployment.apps/demoapp created
   service/demoapp created
   ```
   If the namespace already exists: `namespace/demoapp unchanged` is fine.

3. Wait for the pod to become Ready:
   ```
   kubectl rollout status deployment/demoapp -n demoapp --timeout=120s
   ```
   If the rollout times out, inspect:
   ```
   kubectl describe pod -n demoapp
   kubectl logs -n demoapp -l app=demoapp
   ```
   Most likely cause: ImagePullBackOff — confirm the tag in `demoapp-patch.yaml` matches the tag pushed in Task 1.

4. **Phase 2 SC2 — Verify the pod runs as root:**
   ```
   POD=$(kubectl get pod -n demoapp -l app=demoapp -o jsonpath='{.items[0].metadata.name}')
   kubectl exec ${POD} -n demoapp -- whoami
   ```
   Expected output: `root`

5. Get the NodePort and confirm the app is reachable from the host:
   ```
   curl http://localhost:30080/
   ```
   Expected: `{"status":"ok","app":"demoapp","version":"dev"}`

   If port 30080 is in use, check the actual assigned port:
   ```
   kubectl get svc demoapp -n demoapp -o jsonpath='{.spec.ports[0].nodePort}'
   ```

6. **Phase 2 SC3 — SQL injection proof:**
   ```
   curl "http://localhost:30080/sqli?user=' OR '1'='1"
   ```
   Expected: a response containing `error` (the MySQL error message including the injected SQL) OR actual data rows. The response must NOT be a clean `{"results":[]}` with no error.

   Acceptable responses:
   - `{"error":"ER_ACCESS_DENIED_ERROR: ...","query":"SELECT * FROM users WHERE id = '' OR '1'='1'"}` — shows the injected query in the error
   - Any MySQL error that includes the malformed query string
   - Data rows returned (if DB is running and has data)

   The key proof: the `query` field in the error response shows the injected string was executed, not sanitised.

7. **Phase 2 SC4 — Command injection proof:**
   ```
   curl "http://localhost:30080/cmd?input=id"
   ```
   Expected: `{"stdout":"uid=0(root) gid=0(root) groups=0(root)\n","stderr":"","exit_code":0}`

   The response must contain `uid=0(root)` in `stdout` — this proves:
   - The command was executed (not filtered)
   - The container is running as root (confirming SC2 via a different route)

8. Commit the final state of the overlay (with the real image tag) if not already committed in Task 2:
   ```
   git add deploy/overlays/local/demoapp-patch.yaml
   git status
   ```
   If there are uncommitted changes, commit:
   ```
   git commit -m "chore(02-vulnerable-app): set initial demoapp image tag to <TAG>"
   ```
   If already committed (Task 2 did this), skip.
</action>
<acceptance_criteria>
- `kubectl rollout status deployment/demoapp -n demoapp` exits 0 (pod is Running and Ready)
- `kubectl exec <pod> -n demoapp -- whoami` returns `root`
- `curl "http://localhost:30080/sqli?user=' OR '1'='1"` returns a response containing the injected SQL string in an error message or in actual results — NOT a clean empty response
- `curl "http://localhost:30080/cmd?input=id"` returns `uid=0(root)` in the `stdout` field
- `curl http://localhost:30080/` returns `{"status":"ok",...}` (app health check passes)
</acceptance_criteria>
</task>

</tasks>

## Verification

**Phase 2 success criteria — all four must be true before calling Phase 2 complete:**

1. `trivy image --severity HIGH,CRITICAL --exit-code 1 host.rancher-desktop.internal:5000/demoapp:<TAG>` exits non-zero with at least one CRITICAL CVE — vulnerable base image confirmed
2. `kubectl exec <pod> -n demoapp -- whoami` returns `root` — container running as root confirmed
3. `curl "http://localhost:30080/sqli?user=' OR '1'='1"` returns a response that proves SQL injection is possible (injected query in error message or data leak, not a clean 500 with no output)
4. `curl "http://localhost:30080/cmd?input=id"` returns the container user identity (`uid=0(root)`) in the response body

**must_haves:**
- `deploy/overlays/local/demoapp-patch.yaml` committed with a real SHA tag (never `placeholder`)
- All four Kustomize manifests in `deploy/base/` committed
- `02-02-SUMMARY.md` records the CRITICAL CVE ID(s) Trivy reported (at least one required for thesis documentation)

<output>
After completion, create `.planning/phases/02-vulnerable-app/02-02-SUMMARY.md` containing:
- The image tag (git short SHA) deployed
- The CRITICAL CVE ID(s) Trivy reported (at least one required)
- Confirmation of all four Phase 2 success criteria (pass/fail with actual output snippets)
- The NodePort used (30080 or alternative if changed)
- Any deviations from the plan
</output>
