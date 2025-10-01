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
          args '-u 0 -e PIP_DISABLE_PIP_VERSION_CHECK=1'
        }
      }
      steps {
        sh '''
          python --version
          pip install --no-cache-dir -q flake8
          flake8 .
        '''
      }
    }

    stage('Build') {
      steps {
        sh '''
          docker build -t test-odoo . || echo "kein Dockerfile gefunden – überspringe Build"
        '''
      }
    }

    stage('Deploy') {
      steps {
        sh '''
          echo "HOST WORKSPACE=$WORKSPACE"
          test -f "$WORKSPACE/$COMPOSE_FILE" || { echo "Compose-Datei fehlt: $WORKSPACE/$COMPOSE_FILE"; ls -la "$WORKSPACE"; exit 1; }

          JENKINS_CID="$(hostname)"
          echo "JENKINS_CID=$JENKINS_CID"

          # Compose v2 Image festlegen
          COMPOSE_IMG="docker/compose:2"

          # Debug: Version & Sicht auf Dateien
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --volumes-from "$JENKINS_CID" \
            -w "$WORKSPACE" \
            $COMPOSE_IMG version || true

          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --volumes-from "$JENKINS_CID" \
            -w "$WORKSPACE" \
            $COMPOSE_IMG ls || true

          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --volumes-from "$JENKINS_CID" \
            -w "$WORKSPACE" \
            $COMPOSE_IMG -f "$COMPOSE_FILE" config

          # Aufräumen (falls defekte Reste von vorher)
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --volumes-from "$JENKINS_CID" \
            -w "$WORKSPACE" \
            $COMPOSE_IMG -f "$COMPOSE_FILE" down -v || true

          # Hochfahren
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
          # Warten bis Odoo antwortet
          for i in $(seq 1 90); do
            docker run --rm --network host curlimages/curl:8.9.1 \
              -fsS http://localhost:8069/web/login >/dev/null && { echo "Smoke OK"; exit 0; }
            sleep 2
          done
          echo "Smoke failed"; exit 1
        '''
      }
    }
  }
}
