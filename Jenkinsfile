pipeline {
  agent any

  environment {
    PY_IMAGE = 'python:3.11-slim'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Lint') {
      steps {
        script {
          docker.image(env.PY_IMAGE).inside('-u 0') {
            sh '''
              set -eux
              python --version
              pip install -q --no-cache-dir flake8
              flake8 .
            '''
          }
        }
      }
    }

    stage('Build') {
      steps {
        sh '''
          set -eux
          if [ -f Dockerfile ]; then
            docker build -t test-odoo .
          else
            echo "kein Dockerfile gefunden – überspringe Build"
          fi
        '''
      }
    }

    stage('Deploy') {
      steps {
        sh '''
          set -eux
          WORKSPACE="$(pwd)"
          JENKINS_CID="$(hostname)"

          # Sichere, reproduzierbare Compose Version (v1.29.2)
          COMPOSE_IMG="docker/compose:1.29.2"

          # Compose-File prüfen
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --volumes-from "${JENKINS_CID}" \
            -w "${WORKSPACE}" \
            "${COMPOSE_IMG}" config

          # Stack starten
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --volumes-from "${JENKINS_CID}" \
            -w "${WORKSPACE}" \
            "${COMPOSE_IMG}" up -d
        '''
      }
    }

    stage('Smoke') {
      steps {
        sh '''
          set -eux
          # Warten bis Odoo lauscht
          for i in $(seq 1 60); do
            if docker ps --format '{{.Names}}' | grep -q 'odoo'; then
              break
            fi
            sleep 1
          done

          # Ein sehr einfacher Check: Container läuft & Port gemappt
          docker ps
        '''
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'docker-compose.yml', onlyIfSuccessful: false
    }
  }
}
