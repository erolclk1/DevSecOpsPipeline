pipeline {
  agent { label 'docker-builder' }
  options { timestamps() ; ansiColor('xterm') }
  parameters {
    string(name: 'DOCKERFILE', defaultValue: 'Dockerfile',
           description: 'Dockerfile (vulnerable) or Dockerfile.fixed (patched)')
  }
  environment {
    TRIVY_CACHE = "/home/jenkins/.trivy-cache"
    HOST_REG    = "localhost:5001"
    CLUSTER_REG = "host.rancher-desktop.internal:5001"
    GIT_SHA     = ""
  }
  stages {
    stage('BUILD') {
      steps {
        script { env.GIT_SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim() }
        sh 'docker build -f app/${DOCKERFILE} -t ${HOST_REG}/demoapp:${GIT_SHA} app/'
      }
    }
    stage('SCAN') {
      steps {
        // 1) Evidence FIRST (Pitfall 6): SBOM + JSON report before the gate, so blocked builds still archive artefacts
        sh '''
          trivy image --image-src docker --format cyclonedx \
            --output demoapp-sbom.json --cache-dir "$TRIVY_CACHE" ${HOST_REG}/demoapp:${GIT_SHA}
          trivy image --image-src docker --severity HIGH,CRITICAL --format json \
            --output trivy-report.json --cache-dir "$TRIVY_CACHE" ${HOST_REG}/demoapp:${GIT_SHA} || true
        '''
        // 2) The gate (CI-03): non-zero exit fails the stage and stops the pipeline before PUSH
        sh '''
          trivy image --image-src docker --severity HIGH,CRITICAL --ignore-unfixed \
            --exit-code 1 --scanners vuln --no-progress \
            --cache-dir "$TRIVY_CACHE" ${HOST_REG}/demoapp:${GIT_SHA}
        '''
      }
    }
    stage('PUSH') {
      steps {
        sh 'docker push ${HOST_REG}/demoapp:${GIT_SHA}'
      }
    }
    stage('BUMP') {
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GH_TOKEN')]) {
          sh '''
            yq -i '.spec.template.spec.containers[0].image = "'"${CLUSTER_REG}"'/demoapp:'"${GIT_SHA}"'"' \
              deploy/overlays/local/demoapp-patch.yaml
            git config user.email "jenkins@thesis.local"
            git config user.name  "jenkins-ci"
            git add deploy/overlays/local/demoapp-patch.yaml
            git commit -m "ci: bump demoapp to ${GIT_SHA} [skip ci]"
            git push https://${GH_TOKEN}@github.com/erolclk1/DevSecOpsPipeline.git HEAD:main
          '''
        }
      }
    }
  }
  post {
    always {
      archiveArtifacts artifacts: 'demoapp-sbom.json, trivy-report.json', allowEmptyArchive: true
    }
  }
}
