---
id: "01-02"
title: "End-to-End Pull Verification"
wave: 2
depends_on: ["01-01"]
requirements_addressed: [INFRA-03]
files_modified:
  - cluster/registries.yaml
autonomous: false
must_haves:
  truths:
    - "A pod that references host.rancher-desktop.internal:5000/hello:smoke reaches Running state without ImagePullBackOff"
    - "curl from inside a cluster pod to http://host.rancher-desktop.internal:5000/v2/ returns {}"
    - "cluster/registries.yaml contains the exact hostname that passed both tests"
  artifacts:
    - path: "cluster/registries.yaml"
      provides: "Final, validated registries.yaml with the hostname confirmed to work from inside the VM"
      contains: "host.rancher-desktop.internal:5000"
  key_links:
    - from: "smoke test pod"
      to: "host.rancher-desktop.internal:5000/hello:smoke"
      via: "containerd image pull using mirrors from ~/.rd/k3s/registries.yaml"
      pattern: "Running"
    - from: "curl-test pod"
      to: "http://host.rancher-desktop.internal:5000/v2/"
      via: "in-cluster DNS resolving host.rancher-desktop.internal"
      pattern: "{}"
---

<objective>
Push a minimal smoke-test image to the local registry, run it as a pod in k3s, and verify that (a) the pod reaches `Running` without `ImagePullBackOff`, and (b) from inside a cluster pod the registry HTTP API returns `{}`. If `host.rancher-desktop.internal` does not resolve from inside the VM, fall back to `host.lima.internal` and update `cluster/registries.yaml` to match.

Purpose: Proves the full host→registry→cluster pull chain works. This is the Gate 1 prerequisite for every later phase that pushes an image and expects the cluster to run it.

Output: Running smoke pod (then cleaned up), cluster/registries.yaml updated with the exact working hostname, git commit of the artefact.
</objective>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@CLAUDE.md
@cluster/registries.yaml
</context>

<tasks>

<task id="1" title="Build, push, and pull-test the smoke image">
<read_first>
- cluster/registries.yaml — must match the hostname used in all commands below
- CLAUDE.md — Critical Rules: image tags must be git short SHA or a fixed label like `smoke`, never `:latest`; registry hostname is `host.rancher-desktop.internal:5000`
- .planning/research/PITFALLS.md — Pitfall 2 (cross-network; host.rancher-desktop.internal vs host.lima.internal)
</read_first>
<action>
1. Build the smoke image on the host using a minimal inline Dockerfile:
   ```
   docker build -t host.rancher-desktop.internal:5000/hello:smoke - <<'EOF'
   FROM busybox:latest
   CMD ["echo", "hello from registry"]
   EOF
   ```
   This uses stdin to avoid needing a Dockerfile on disk. The tag is `smoke` (not `:latest`) per the project's image-tag rule.

2. Push the image to the local registry:
   ```
   docker push host.rancher-desktop.internal:5000/hello:smoke
   ```
   On Rancher Desktop, if `host.rancher-desktop.internal` does not resolve for Docker push, use `localhost:5000` for the PUSH step only (the host's Docker daemon uses localhost). The CLUSTER PULL must always reference `host.rancher-desktop.internal:5000`:
   ```
   # Alternative push path (host-side only):
   docker tag host.rancher-desktop.internal:5000/hello:smoke localhost:5000/hello:smoke
   docker push localhost:5000/hello:smoke
   # Then re-tag with the cluster-resolvable name:
   docker tag localhost:5000/hello:smoke host.rancher-desktop.internal:5000/hello:smoke
   ```

3. Verify the tag appears in the registry:
   ```
   curl http://host.rancher-desktop.internal:5000/v2/hello/tags/list
   ```
   Expected response: `{"name":"hello","tags":["smoke"]}`

4. Run the smoke pod:
   ```
   kubectl run pull-test \
     --image=host.rancher-desktop.internal:5000/hello:smoke \
     --restart=Never
   ```

5. Watch for the pod to reach `Completed` (busybox `echo` exits 0 immediately) or `Running`:
   ```
   kubectl get pod pull-test --watch
   ```
   The pod status must NOT be `ErrImagePull` or `ImagePullBackOff`.
   Wait up to 60 seconds. If it stays in `ContainerCreating` beyond 30 s, inspect:
   ```
   kubectl describe pod pull-test
   ```
   Look at the `Events:` section. `Successfully pulled image` confirms the pull chain works.

6. Once the pod has completed, clean it up:
   ```
   kubectl delete pod pull-test
   ```

**If ImagePullBackOff occurs — hostname fallback procedure:**
   a. Check whether `host.lima.internal` resolves inside the VM:
      ```
      kubectl run dns-probe --rm -it --image=busybox --restart=Never -- nslookup host.rancher-desktop.internal
      ```
      If `nslookup host.rancher-desktop.internal` fails but `nslookup host.lima.internal` succeeds, you must use `host.lima.internal` everywhere.

   b. Update `~/.rd/k3s/registries.yaml` — replace every occurrence of `host.rancher-desktop.internal` with `host.lima.internal`.

   c. Restart Rancher Desktop (`rdctl shutdown && rdctl start`) and wait for "Kubernetes: Running".

   d. Re-push the smoke image using the new hostname and retry `kubectl run`.

   e. Update `cluster/registries.yaml` in the repo to match whichever hostname worked. This is the authoritative artefact — the rest of the project uses this hostname.

   Note: never hardcode an IP address — it changes on DHCP roam and VM restarts.
</action>
<acceptance_criteria>
- `kubectl get pod pull-test` (before deletion) shows STATUS `Completed` or `Running` — never `ImagePullBackOff` or `ErrImagePull`
- `kubectl describe pod pull-test` Events section contains the string `Successfully pulled image`
- `curl http://host.rancher-desktop.internal:5000/v2/hello/tags/list` returns `{"name":"hello","tags":["smoke"]}`
- `kubectl delete pod pull-test` exits 0 (cleanup confirmed)
</acceptance_criteria>
</task>

<task id="2" title="Verify registry reachable from inside the cluster, finalise artefact, commit">
<read_first>
- cluster/registries.yaml — confirm it contains the hostname that worked in Task 1
- CLAUDE.md — registry hostname rules
</read_first>
<action>
1. Run a one-shot curl pod inside the cluster to verify the registry HTTP API is reachable from inside the VM:
   ```
   kubectl run curl-test \
     --rm -it \
     --image=curlimages/curl \
     --restart=Never \
     -- curl -s http://host.rancher-desktop.internal:5000/v2/
   ```
   (Replace `host.rancher-desktop.internal` with `host.lima.internal` if that was the fallback hostname determined in Task 1.)

   Expected output printed to the terminal: `{}`

   If the command hangs for more than 30 seconds without output, press Ctrl+C. This indicates DNS is not resolving inside the VM. In that case:
   - Re-run the dns-probe from Task 1 fallback procedure.
   - Determine the correct hostname empirically.
   - Update `~/.rd/k3s/registries.yaml` and `cluster/registries.yaml` to the working hostname.
   - Restart Rancher Desktop and retry.

2. Ensure `cluster/registries.yaml` in the repo reflects the hostname that actually worked (either `host.rancher-desktop.internal` or `host.lima.internal`):
   ```
   cat cluster/registries.yaml
   ```
   The file must contain exactly:
   ```yaml
   mirrors:
     "<WORKING_HOSTNAME>:5000":
       endpoint:
         - "http://<WORKING_HOSTNAME>:5000"
   configs:
     "<WORKING_HOSTNAME>:5000":
       tls:
         insecure_skip_verify: true
   ```
   Where `<WORKING_HOSTNAME>` is whichever hostname succeeded in both Task 1 and this task's curl-test.

3. Stage and commit the artefact:
   ```
   git add cluster/registries.yaml
   git commit -m "feat(01-bootstrap): add verified registries.yaml for local registry"
   ```

4. Record the following for the SUMMARY (do not skip — these resolve open questions in STATE.md):
   - The exact working registry hostname (`host.rancher-desktop.internal` or `host.lima.internal`)
   - The exact k3s server version from `kubectl version` (resolves Open Question 3)
   - Rancher Desktop VM memory setting confirmed (6 GB)
</action>
<acceptance_criteria>
- `kubectl run curl-test --rm -it --image=curlimages/curl --restart=Never -- curl -s http://<WORKING_HOSTNAME>:5000/v2/` prints `{}` to the terminal
- `cluster/registries.yaml` in the repo contains `insecure_skip_verify: true` and the correct working hostname
- `git log --oneline -1` shows the commit `feat(01-bootstrap): add verified registries.yaml for local registry`
- `cat cluster/registries.yaml` output matches `~/.rd/k3s/registries.yaml` byte-for-byte (diff is empty)
</acceptance_criteria>
</task>

</tasks>

## Verification

**Phase 1 success criteria — all four must be true before calling Phase 1 complete:**

1. `kubectl get nodes` shows exactly one node in `Ready` state
2. `curl http://<WORKING_HOSTNAME>:5000/v2/` from the host returns `{}`
3. `kubectl describe pod pull-test` (captured before deletion) showed `Successfully pulled image "host.rancher-desktop.internal:5000/hello:smoke"` — pod reached `Running`/`Completed` without `ImagePullBackOff`
4. A one-shot `curlimages/curl` pod inside the cluster returned `{}` when hitting `http://<WORKING_HOSTNAME>:5000/v2/`

**must_haves:**
- `cluster/registries.yaml` committed to the repo with the exact working mirror syntax
- Working registry hostname documented (resolves STATE.md Open Question 1 and 2)
- k3s server version recorded (resolves STATE.md Open Question 3)
- All four ROADMAP Phase 1 success criteria confirmed true

<output>
After completion, create `.planning/phases/01-bootstrap/01-02-SUMMARY.md` containing:
- The exact working registry hostname (host.rancher-desktop.internal or host.lima.internal)
- The k3s server version string from `kubectl version`
- Confirmation of all four Phase 1 success criteria (pass/fail)
- Any unexpected findings (e.g. hostname fallback was required, Docker Desktop conflict was encountered)
</output>
