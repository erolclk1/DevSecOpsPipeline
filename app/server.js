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
