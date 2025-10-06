pipeline {
  agent any
  options { timestamps() }

  environment {
    // Öffentliche URL für externen Smoke-Test (anpassen, falls nötig)
    PUBLIC_URL = "http://91.107.228.241:8069/web/login"
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Lint') {
      steps {
        script {
          docker.image('python:3.11-slim').inside('-u 0') {
            sh '''
              set -eux
              pip install --no-cache-dir -q flake8
              flake8 .
            '''
          }
        }
      }
    }

    // ---- Neu hinzugefügt: Build (ohne Einfluss auf Deploy) ----
    stage('Build') {
      steps {
        sh '''
          set -eux
          if [ -f Dockerfile ]; then
            echo "Dockerfile gefunden – baue Test-Image…"
            DOCKER_BUILDKIT=1 docker build -t odoo-custom:${BUILD_NUMBER} .
            docker image ls | grep odoo-custom | head -n 1 || true
          else
            echo "Kein Dockerfile im Repo – überspringe Build."
          fi
        '''
      }
    }

    stage('Deploy') {
      steps {
        sh '''
          set -eux
          echo "Workspace: $WORKSPACE"

          # docker compose v2 lokal in den Workspace legen (falls nicht da)
          mkdir -p "$WORKSPACE/.docker/cli-plugins"
          if [ ! -x "$WORKSPACE/.docker/cli-plugins/docker-compose" ]; then
            echo "Lade docker compose v2.29.7…"
            curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
              -o "$WORKSPACE/.docker/cli-plugins/docker-compose"
            chmod +x "$WORKSPACE/.docker/cli-plugins/docker-compose"
          fi

          docker compose version

          # Compose starten
          test -f docker-compose.yml
          docker compose -f docker-compose.yml up -d

          # kurze Log-Zeilen ausgeben
          docker compose logs --no-color --tail=50 odoo || true
        '''
      }
    }

    stage('Smoke (internal)') {
      steps {
        sh '''
          set -eux
          echo "Smoke-Test: warte bis Odoo (im Container) antwortet…"
          for i in $(seq 1 30); do
            if docker compose exec -T odoo python3 - <<'PY'
import urllib.request, sys
try:
    urllib.request.urlopen("http://localhost:8069/web/login", timeout=3)
    print("OK")
    sys.exit(0)
except Exception as e:
    sys.exit(1)
PY
            then
              echo "Odoo OK (intern nach $i Versuchen)."
              exit 0
            fi
            echo "Warte auf Odoo ($i/30)…"; sleep 3
          done
          echo "Smoke-Test (intern) fehlgeschlagen"
          exit 1
        '''
      }
    }

    stage('Smoke (external)') {
      steps {
        sh '''
          set -eux
          echo "Externer Smoke-Test gegen $PUBLIC_URL"
          for i in $(seq 1 15); do
            if docker run --rm curlimages/curl:8.9.1 -fsS "$PUBLIC_URL" >/dev/null; then
              echo "Odoo extern erreichbar (Versuch $i)."
              exit 0
            fi
            echo "Warte extern ($i/15)…"; sleep 3
          done
          echo "Externer Smoke-Test fehlgeschlagen"
          exit 1
        '''
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'docker-compose.yml, config/**, Jenkinsfile', allowEmptyArchive: true
    }
  }
}
