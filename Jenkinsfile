pipeline {
  agent any

  environment {
    // Pfad für den docker compose v2 Plugin-Binary (wird heruntergeladen)
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
    COMPOSE_VERSION = "v2.29.7"
    COMPOSE_URL = "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Lint') {
      agent { label '' }
      steps {
        script {
          docker.image('python:3.11-slim').inside("-u 0") {
            sh '''
              set -eux
              python --version
              pip install --no-cache-dir flake8
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
          # Optionaler Build. Falls kein Dockerfile vorhanden ist, nicht failen.
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

          echo "Workspace: $WORKSPACE"

          # Compose v2 Plugin lokal in den Workspace laden (einmal pro Joblauf)
          mkdir -p "${DOCKER_CONFIG}/cli-plugins"
          if [ ! -x "${DOCKER_CONFIG}/cli-plugins/docker-compose" ]; then
            echo "Lade docker compose ${COMPOSE_VERSION}…"
            curl -fsSL "${COMPOSE_URL}" -o "${DOCKER_CONFIG}/cli-plugins/docker-compose"
            chmod +x "${DOCKER_CONFIG}/cli-plugins/docker-compose"
          fi

          # Zeige Version zur Kontrolle (sollte v2.x sein)
          docker compose version

          # Sanity-Check: compose-Datei existiert?
          test -f docker-compose.yml

          # Stack hochfahren (Host-Docker via /var/run/docker.sock)
          docker compose -f docker-compose.yml up -d

          # Warten, bis der DB-Container gesund ist (optional: wenn Healthcheck in compose.yml vorhanden)
          # docker compose ps

          # Odoo-Logs kurz zeigen (nur zur Diagnose)
          docker compose logs --no-color --tail=50 odoo || true
        '''
      }
    }

    stage('Smoke') {
      steps {
        sh '''
          set -eux
          # Wir prüfen den HTTP-Login-Endpunkt mit Retries
          # Falls Jenkins und Odoo auf demselben Host laufen, hier "localhost".
          URL="http://localhost:8069/web/login"

          echo "Smoke-Test gegen ${URL}"
          for i in $(seq 1 30); do
            if curl -fsS "${URL}" >/dev/null; then
              echo "Smoke OK"
              exit 0
            fi
            echo "Warte auf Odoo (${i}/30)…"
            sleep 3
          done

          echo "Smoke-Test fehlgeschlagen"
          exit 1
        '''
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'docker-compose.yml, odoo.conf', allowEmptyArchive: true
    }
  }
}
