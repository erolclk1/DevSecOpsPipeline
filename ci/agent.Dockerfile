FROM jenkins/inbound-agent:latest-jdk21
USER root

# Bake docker CLI + Trivy v0.72.0 + yq v4.45.1 + git so every pipeline stage
# runs on this agent (controller has numExecutors=0). Docker talks to the host
# daemon via the socket mounted by docker-compose (agent only, never controller).
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates git \
 && curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-28.3.3.tgz \
    | tar -xz -C /tmp \
 && mv /tmp/docker/docker /usr/local/bin/docker \
 && chmod +x /usr/local/bin/docker \
 && rm -rf /tmp/docker \
 && curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin v0.72.0 \
 && curl -sfL https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_amd64 -o /usr/local/bin/yq \
 && chmod +x /usr/local/bin/yq \
 && rm -rf /var/lib/apt/lists/*

COPY agent-entrypoint.sh /usr/local/bin/agent-entrypoint.sh
RUN chmod +x /usr/local/bin/agent-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/agent-entrypoint.sh"]
