pipeline {
  agent any
  options { timestamps() }
  environment {
    COMPOSE_FILE = 'docker-compose.yml'
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Lint') {
      agent {
        docker {
          image 'python:3.11-slim'
          // root inside the ephemeral lint container (nur für pip install von flake8)
          args '-u 0 -e PIP_DISABLE_PIP_VERSION_CHECK=1'
        }
      }
      steps {
        sh '''
          set -eux
          python --version
          pip install --no-cache-dir -q flake8
          flake8 .
        '''
      }
    }

    stage('Build') {
      steps {
        sh '''
          set -eux
          # Optional: nur bauen, wenn ein Dockerfile vorhanden ist
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
          echo "HOST WORKSPACE=$WORKSPACE"
          test -f "$WORKSPACE/$COMPOSE_FILE" || { echo "Compose-Datei fehlt: $WORKSPACE/$COMPOSE_FILE"; ls -la "$WORKSPACE"; exit 1; }

          # Container-ID/Hostname des Jenkins-Containers (für --volumes-from)
          JENKINS_CID="$(hostname)"
          echo "JENKINS_CID=$JENKINS_CID"

          # Compose v2 (Go-Binary)
          COMPOSE_IMG="docker/compose:latest"

          # Sichtprüfung / Debug
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --volumes-from "$JENKINS_CID" \
            -w "$WORKSPACE" \
            $COMPOSE_IMG version || true

          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --volumes-from "$JENKINS_CID" \
            -w "$WORKSPACE" \
            $COMPOSE_IMG -f "$COMPOSE_FILE" config

          # Sauber aufräumen und neu starten
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --volumes-from "$JENKINS_CID" \
            -w "$WORKSPACE" \
            $COMPOSE_IMG -f "$COMPOSE_FILE" down -v || true

          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --volumes-from "$JENKINS_CID" \
            -w "$WORKSPACE" \
            $COMPOSE_IMG -f "$COMPOSE_FILE" up -d
        '''
      }
    }

    stage('Smoke') {
      steps {
        sh '''
          set -eux
          # warte bis Odoo antwortet (max ~3 Minuten)
          for i in $(seq 1 90); do
            if docker run --rm --network host curlimages/curl:8.9.1 -fsS http://localhost:8069/web/login >/dev/null; then
              echo "Smoke OK"
              exit 0
            fi
            sleep 2
          done
          echo "Smoke failed"
          exit 1
        '''
      }
    }
  }
}
