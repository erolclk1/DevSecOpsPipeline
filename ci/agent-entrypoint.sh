#!/usr/bin/env bash
# Auto-connect the inbound agent by fetching its JNLP secret with admin creds.
# No manual secret paste -> fully reproducible from docker-compose up.
set -euo pipefail
: "${JENKINS_URL:?JENKINS_URL is required}"
: "${JENKINS_AGENT_NAME:=docker-builder}"
: "${JENKINS_ADMIN_USER:?JENKINS_ADMIN_USER is required}"
: "${JENKINS_ADMIN_PASSWORD:?JENKINS_ADMIN_PASSWORD is required}"

echo "Waiting for controller at ${JENKINS_URL} ..."
until curl -sf -o /dev/null "${JENKINS_URL}/login"; do sleep 3; done

SECRET=""
for i in $(seq 1 30); do
  SECRET=$(curl -sf -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
    "${JENKINS_URL}/computer/${JENKINS_AGENT_NAME}/slave-agent.jnlp" \
    | sed -n 's/.*<argument>\([a-f0-9]\{64\}\)<\/argument>.*/\1/p' | head -1) || true
  [ -n "${SECRET}" ] && break
  echo "Agent secret not ready yet (attempt ${i}/30) ..."
  sleep 3
done

[ -n "${SECRET}" ] || { echo "Failed to obtain agent secret for ${JENKINS_AGENT_NAME}"; exit 1; }

exec jenkins-agent -url "${JENKINS_URL}" -secret "${SECRET}" -name "${JENKINS_AGENT_NAME}" -workDir /home/jenkins/agent
