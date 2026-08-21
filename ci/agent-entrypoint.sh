#!/usr/bin/env bash
# Auto-connect the inbound agent by fetching its JNLP secret with admin creds.
# No manual secret paste -> fully reproducible from docker-compose up.
set -euo pipefail
: "${JENKINS_URL:?JENKINS_URL is required}"
: "${JENKINS_AGENT_NAME:=docker-builder}"
: "${JENKINS_ADMIN_USER:?JENKINS_ADMIN_USER is required}"
: "${JENKINS_ADMIN_PASSWORD:?JENKINS_ADMIN_PASSWORD is required}"

# ── Docker socket access ──────────────────────────────────────────────────────
# The socket is mounted from the host, so its GID may differ from the
# docker group GID baked into the agent image.
if [[ -S /var/run/docker.sock ]]; then
  DOCKER_GID="$(stat -c '%g' /var/run/docker.sock)"

  if [[ "${DOCKER_GID}" = "0" ]]; then
    usermod -aG root jenkins
  else
    if getent group docker >/dev/null 2>&1; then
      EXISTING_DOCKER_GID="$(getent group docker | cut -d: -f3)"

      if [[ "${EXISTING_DOCKER_GID}" != "${DOCKER_GID}" ]]; then
        groupdel docker
        groupadd -g "${DOCKER_GID}" docker
      fi
    else
      groupadd -g "${DOCKER_GID}" docker
    fi

    usermod -aG docker jenkins
  fi
fi

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