FROM jenkins/jenkins:2.555.3-lts-jdk21

# Disable the setup wizard (CI-01: no UI wizard, fully code-provisioned)
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

# JCasC config location (file mounted read-only by docker-compose)
ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml

# Bake pinned plugins into the image (CI-07: explicit versions, no :latest)
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt
