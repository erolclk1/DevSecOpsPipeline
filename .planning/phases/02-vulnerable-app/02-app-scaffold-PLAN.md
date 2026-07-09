---
id: "02-01"
title: "Vulnerable App Scaffold + Dockerfile + Trivy Validation"
wave: 1
depends_on: ["01-02"]
requirements_addressed: [APP-01, APP-02, APP-03, APP-04]
files_modified:
  - app/server.js
  - app/package.json
  - app/package-lock.json
  - app/Dockerfile
  - app/.dockerignore
autonomous: true
must_haves:
  truths:
    - "app/server.js exposes /sqli?user= with string-concatenated SQL query (no parameterisation)"
    - "app/server.js exposes /cmd?input= with child_process.exec using unvalidated input"
    - "app/Dockerfile uses a pinned outdated Node.js base image (node:14.21.3-alpine or equivalent old digest)"
    - "app/Dockerfile has no USER directive so the container runs as root"
    - "trivy image --severity HIGH,CRITICAL --exit-code 1 exits non-zero with at least one CRITICAL CVE when built"
  artifacts:
    - path: "app/server.js"
      provides: "Vulnerable Node.js REST API with two attack-ready endpoints"
      contains: "INTENTIONALLY VULNERABLE"
    - path: "app/Dockerfile"
      provides: "Dockerfile with old pinned base image that guarantees Trivy findings"
      contains: "node:14"
    - path: "app/.dockerignore"
      provides: "Build context exclusion list"
      contains: "node_modules"
  key_links:
    - from: "app/Dockerfile"
      to: "host.rancher-desktop.internal:5000/demoapp:<tag>"
      via: "docker build + docker push on Windows target machine"
      pattern: "CRITICAL CVE on trivy scan"
---

<objective>
Scaffold a minimal Node.js 22 REST API in `app/` with two deliberately vulnerable endpoints — SQL injection and command injection — and a Dockerfile that uses a pinned outdated base image so Trivy always reports at least one CRITICAL CVE.

This is code-authoring work done on the **macOS dev machine** (Claude Code). The built image will be tested on the **Windows target machine** in the next plan.

Purpose: Create the demo app artefact that is the core proof-of-concept for the thesis. The vulnerability design must be deterministic — the same exploits must work reliably in every demo rehearsal.

Output: `app/` directory with `server.js`, `package.json`, `Dockerfile`, `.dockerignore` — all committed to Git, ready for `docker build` on the Windows target machine.
</objective>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@CLAUDE.md
</context>

<tasks>

<task id="1" title="Scaffold the Node.js vulnerable REST API">
<read_first>
- CLAUDE.md — Critical Rules (registry hostname, image tag rules)
- .planning/ROADMAP.md — Phase 2 tasks (exact endpoint specs and pitfall notes)
- .planning/research/SUMMARY.md — Demo app section (Node.js 22 LTS chosen, SQLi via string concat, CMDi via child_process.exec)
</read_first>
<action>
Create the `app/` directory with the following files:

**1. `app/package.json`**

```json
{
  "name": "demoapp",
  "version": "1.0.0",
  "description": "Deliberately vulnerable demo REST API — thesis artefact",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "4.18.2",
    "mysql": "2.18.1"
  }
}
```

Notes:
- `express` 4.18.2 — stable, well-understood.
- `mysql` 2.18.1 (NOT `mysql2`) — the older `mysql` package does NOT support parameterised queries natively in the way that prevents concatenation-based SQLi. This is intentional: using `mysql` makes it harder to accidentally write safe queries.
- No `devDependencies` — keep the image small and the vulnerability surface explicit.

**2. `app/server.js`**

```javascript
'use strict';

const express = require('express');
const mysql = require('mysql');
const { exec } = require('child_process');

const app = express();
const PORT = process.env.PORT || 3000;

// Database connection — points at a MySQL host (may not be running; errors are surfaced to the caller, which is the proof of exploitability)
const db = mysql.createConnection({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASS || 'password',
  database: process.env.DB_NAME || 'demo'
});

db.connect((err) => {
  if (err) {
    console.warn('DB connection failed (expected in demo mode):', err.message);
  }
});

app.get('/', (req, res) => {
  res.json({ status: 'ok', app: 'demoapp', version: process.env.APP_VERSION || 'dev' });
});

// INTENTIONALLY VULNERABLE: SQL injection via string concatenation (OWASP A03:2021 Injection)
app.get('/sqli', (req, res) => {
  const user = req.query.user || '';
  // INTENTIONALLY VULNERABLE: user input concatenated directly into SQL query
  const query = "SELECT * FROM users WHERE id = '" + user + "'";
  console.log('Executing query:', query);
  db.query(query, (err, results) => {
    if (err) {
      // Surface the SQL error — proof of injection exploitability
      return res.status(500).json({ error: err.message, query: query });
    }
    res.json({ results });
  });
});

// INTENTIONALLY VULNERABLE: OS command injection via child_process.exec (OWASP A03:2021 Injection)
app.get('/cmd', (req, res) => {
  const input = req.query.input || 'echo hello';
  // INTENTIONALLY VULNERABLE: unvalidated user input passed directly to shell
  exec(input, { timeout: 5000 }, (err, stdout, stderr) => {
    res.json({
      stdout: stdout || '',
      stderr: stderr || '',
      exit_code: err ? err.code : 0
    });
  });
});

app.listen(PORT, () => {
  console.log(`demoapp listening on port ${PORT}`);
});
```

Key design decisions:
- `/sqli?user=` uses `mysql` package with raw string concatenation. The DB error message is returned in the response body — this is the "proof of exploitability" for the success criterion.
- `/cmd?input=` uses `child_process.exec` (NOT `execFile` — `exec` passes input to a shell, enabling `; id`, `| cat /etc/shadow`, etc.).
- Both vulnerable lines are marked `// INTENTIONALLY VULNERABLE` — required by ROADMAP task 1.
- The `/` health endpoint returns `{ status: 'ok' }` for use as a Kubernetes readiness probe.
- `exec` is destructured from `child_process` (not `require('child_process').exec`) to keep the import clear.

**3. `app/.dockerignore`**

```
node_modules
.git
.env
.env.*
npm-debug.log
*.md
```

This prevents `node_modules`, `.git`, and any `.env` files from entering the build context (addresses ROADMAP Pitfall 20).
</action>
<acceptance_criteria>
- `app/package.json` exists and lists `express` and `mysql` as dependencies
- `app/server.js` exists and contains `// INTENTIONALLY VULNERABLE` on both the SQL concatenation line and the exec call
- `app/server.js` uses `exec(input, ...)` from `child_process` (not `execFile`)
- `app/server.js` uses string concatenation (`+`) in the SQL query (not a parameterised query)
- `app/.dockerignore` exists and contains `node_modules` and `.git`
</acceptance_criteria>
</task>

<task id="2" title="Write the Dockerfile with a pinned outdated base image">
<read_first>
- CLAUDE.md — Critical Rules: image tags must be git short SHA or pinned; never :latest
- .planning/ROADMAP.md — Phase 2 task 2: use node:14.0.0-alpine or equivalent old digest; no USER directive; container runs as root
- .planning/research/SUMMARY.md — "Vulnerable demo app: ... deliberately outdated base image (node:14 or python:3.9 vintage), runs as root initially"
</read_first>
<action>
Create `app/Dockerfile`:

```dockerfile
FROM node:14.21.3-alpine

WORKDIR /app

COPY package.json package-lock.json* ./

RUN npm install --production

COPY server.js ./

ENV PORT=3000

EXPOSE 3000

CMD ["node", "server.js"]
```

Design decisions:
- `node:14.21.3-alpine` — Node.js 14 reached End of Life in April 2023. This version (last 14.x LTS) carries numerous HIGH and CRITICAL CVEs that Trivy reliably detects. Using a specific version tag (not a digest) is intentional — it must be reproducible without digest pinning complexity in the thesis context.
- **No `USER` directive** — the container runs as root (uid 0). This is deliberate: it satisfies APP-04 (root container requirement) and demonstrates the Kyverno `disallow-privileged-containers` admission violation in Phase 3.
- `npm install --production` — installs only runtime deps (no devDeps); keeps the layer small and the CVE surface focused on the base image.
- `package-lock.json*` with glob — handles the case where the lock file may not exist yet on first clone.

**Why `node:14.21.3-alpine` guarantees CVEs:**
Node.js 14 + Alpine 3.x carries CVEs in OpenSSL, expat, zlib, and node itself (V8, libuv). As of 2026 Trivy reports these as CRITICAL. If for any reason this specific tag no longer shows CVEs in a future Trivy DB version, replace with the sha256 digest of this tag — freeze the exact layer to guarantee findings.

**Verify locally (macOS dev machine — optional sanity check before committing):**
If Docker is available on the dev machine, run:
```
cd app/
docker build -t demoapp:local .
trivy image --severity HIGH,CRITICAL demoapp:local 2>/dev/null | head -30
```
Expected: at least one CRITICAL finding. If clean, the base image or Trivy DB is wrong.

**Note:** The definitive Trivy scan runs on the Windows target machine in Plan 02-02 — this step is just authoring the Dockerfile correctly.
</action>
<acceptance_criteria>
- `app/Dockerfile` exists and starts with `FROM node:14.21.3-alpine`
- `app/Dockerfile` does NOT contain a `USER` directive
- `app/Dockerfile` runs `npm install --production`
- `app/Dockerfile` exposes port 3000
- `app/Dockerfile` CMD is `["node", "server.js"]`
</acceptance_criteria>
</task>

<task id="3" title="Run npm install to generate package-lock.json, then commit all app artefacts">
<read_first>
- app/package.json — confirm dependencies are listed
- app/.dockerignore — confirm node_modules is excluded
</read_first>
<action>
**Note:** This task runs on the **macOS dev machine** where Node.js may or may not be available. The goal is to generate `package-lock.json` for reproducible builds. If Node.js is not installed locally, skip the npm step and use the alternative below.

**Option A — Node.js available on dev machine:**
```
cd app/
npm install
```
This creates `node_modules/` and `package-lock.json`. Do NOT commit `node_modules/` (it's in `.dockerignore`; add it to the root `.gitignore` if not already excluded).

**Option B — Node.js NOT available on dev machine:**
Create a minimal `package-lock.json` by running npm inside Docker:
```
docker run --rm -v "$(pwd)/app:/app" -w /app node:22-alpine npm install
```
This generates `package-lock.json` without installing Node.js locally.

**After `npm install` (either option):**

Verify the lock file exists:
```
ls -la app/package-lock.json
```

Update `.gitignore` at repo root to exclude `node_modules`:
```
# Add to .gitignore if not already present:
node_modules/
```

Stage and commit all app artefacts:
```
git add app/server.js app/package.json app/package-lock.json app/Dockerfile app/.dockerignore
git commit -m "feat(02-vulnerable-app): scaffold vulnerable Node.js API with SQLi and CMDi endpoints"
```

Commit message format follows the project convention (phase prefix + imperative description).
</action>
<acceptance_criteria>
- `app/package-lock.json` exists (generated by npm install)
- `node_modules/` is NOT staged or committed (excluded by .dockerignore and .gitignore)
- `git log --oneline -1` shows the commit `feat(02-vulnerable-app): scaffold vulnerable Node.js API with SQLi and CMDi endpoints`
- `git diff HEAD` is empty (all artefacts committed)
- `grep 'node_modules' .gitignore` returns a match (node_modules is excluded from the repo)
</acceptance_criteria>
</task>

</tasks>

## Verification

**must_haves:**
- `app/server.js` contains `// INTENTIONALLY VULNERABLE` markers on both the SQL concatenation line and the exec call
- `app/Dockerfile` uses `node:14.21.3-alpine` base (no USER directive, no :latest)
- `app/.dockerignore` excludes `node_modules` and `.git`
- All files are committed to Git — next plan can `git pull` on the Windows machine and immediately `docker build`

<output>
After completion, create `.planning/phases/02-vulnerable-app/02-01-SUMMARY.md` containing:
- Confirmation that all 3 app artefacts exist (server.js, Dockerfile, .dockerignore)
- The exact base image tag used in the Dockerfile
- The git commit SHA for the app scaffold commit
- Any deviation from the plan (e.g. Option B used for npm install, or base image tag changed)
</output>
