# demoapp — Intentionally Vulnerable Demo Application

> **WARNING:** This application is deliberately insecure for thesis demonstration purposes.
> It MUST NOT be deployed outside a **local, isolated environment**.
> Do NOT expose it on any network interface accessible from the internet.

This Node.js REST API contains four documented vulnerabilities that demonstrate the three
security control layers of the thesis pipeline: Trivy (build-time), Kyverno (deploy-time),
and Falco (runtime).

---

## Vulnerabilities

### OWASP A03:2021 — Injection (SQL Injection)

| Property | Value |
|----------|-------|
| Endpoint | `GET /sqli?user=<input>` |
| Vulnerable file | `app/server.js`, line 32 |
| Vulnerable code | `const query = "SELECT * FROM users WHERE id = '" + user + "'"` |
| Why vulnerable | User input is concatenated directly into the SQL query string — no parameterisation, no escaping |
| Attack example | `curl "http://localhost:<nodeport>/sqli?user=' OR '1'='1"` |
| Expected result | Returns all rows from the `users` table (authentication bypass) |
| Falco rule triggered | None (application-layer attack; Falco operates at syscall level) |
| Covered by | `attacks/sqli.py` |

The `// INTENTIONALLY VULNERABLE` comment on line 28 marks this endpoint in the source code.

---

### OWASP A03:2021 — Injection (OS Command Injection)

| Property | Value |
|----------|-------|
| Endpoint | `GET /cmd?input=<input>` |
| Vulnerable file | `app/server.js`, line 47 |
| Vulnerable code | `exec(input, { timeout: 5000 }, (err, stdout, stderr) => { ... })` |
| Why vulnerable | The `input` query parameter is passed directly to `child_process.exec` — a shell is invoked with unvalidated user input |
| Attack example | `curl "http://localhost:<nodeport>/cmd?input=id"` |
| Expected result | Returns the container user identity (e.g., `uid=0(root)`) |
| Falco rules triggered | `reverse-shell` (if reverse shell payload used), `shell-from-webapp` (bash/sh spawned as child of node process) |
| Covered by | `attacks/reverse_shell.sh` |

The `// INTENTIONALLY VULNERABLE` comment on line 43 marks this endpoint in the source code.

---

### OWASP A06:2021 — Vulnerable and Outdated Components

| Property | Value |
|----------|-------|
| Vulnerable file | `app/Dockerfile` |
| Base image | `node:14.21.3-alpine` (pinned outdated version) |
| Why vulnerable | Node.js 14 is end-of-life with known HIGH and CRITICAL CVEs in the OS package layer |
| Detection | `trivy image --severity HIGH,CRITICAL --exit-code 1 <image>` exits non-zero |
| Pipeline effect | Jenkins SCAN stage fails; image is NOT pushed to registry (Scenario 1) |
| Fix | `app/Dockerfile.fixed` uses `node:22-alpine` — Trivy reports 0 CRITICAL CVEs from the npm tree |

---

### OWASP A05:2021 — Security Misconfiguration

| Property | Value |
|----------|-------|
| Vulnerable file | `app/Dockerfile` |
| Issue | No `USER` directive — container process runs as **root** (uid=0) |
| Verification | `kubectl exec <pod> -n demoapp -- whoami` returns `root` |
| Risk | Any command injection (A03) runs with root privileges inside the container |
| Falco rules triggered | `read-sensitive-file` when root reads `/etc/shadow`; `package-management-in-container` when root runs `apk add` |
| Covered by | `attacks/privilege_probe.sh` |

---

## Attack Scripts

| Script | Vulnerability Exercised | Falco Rules |
|--------|------------------------|-------------|
| `attacks/sqli.py` | A03 — SQL Injection | (none — app layer) |
| `attacks/reverse_shell.sh` | A03 — OS Command Injection | `reverse-shell`, `shell-from-webapp` |
| `attacks/privilege_probe.sh` | A05 — Security Misconfiguration | `read-sensitive-file`, `package-management-in-container` |

All scripts hard-code `localhost` and cluster-internal targets. They include a safety comment
documenting the ethical constraint: no external targets.

---

## Endpoints

| Endpoint | Method | Parameters | Purpose |
|----------|--------|------------|---------|
| `/` | GET | -- | Status check (returns `{"status":"ok"}`) |
| `/sqli` | GET | `user` (string) | SQL injection demo |
| `/cmd` | GET | `input` (string) | OS command injection demo |

---

## Running Locally (for development only)

```bash
cd app
npm install
node server.js
# Server listens on PORT env var (default 3000)
```

For the full pipeline demo, use:

```bash
make demo-1   # vulnerable image -- Trivy blocks the build
make demo-2   # fixed image -- ArgoCD deploys via GitOps
make demo-3   # live attack -- Falco detects in real time
```

---

## References

- [OWASP Top 10 2021 — A03: Injection](https://owasp.org/Top10/A03_2021-Injection/)
- [OWASP Top 10 2021 — A05: Security Misconfiguration](https://owasp.org/Top10/A05_2021-Security_Misconfiguration/)
- [OWASP Top 10 2021 — A06: Vulnerable and Outdated Components](https://owasp.org/Top10/A06_2021-Vulnerable_and_Outdated_Components/)
- [CWE-89: SQL Injection](https://cwe.mitre.org/data/definitions/89.html)
- [CWE-78: OS Command Injection](https://cwe.mitre.org/data/definitions/78.html)
