pipeline {
  agent any
  options {
    timestamps()
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
          docker.image('python:3.11-slim').inside('-u 0') {
            sh '''
              set -eux
              python --version
              pip install -q flake8
              flake8 .
            '''
          }
        }
      }
    }

    stage('Build (optional)') {
      when { expression { return false } } // aktuell deaktiviert; später aktivierbar
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

    stage('Deploy DEV') {
      steps {
        sh '''
          set -eux
          echo "Workspace: $WORKSPACE"

          # Compose v2 im Jenkins-Workspace bereitstellen (CLI-Plugin)
          export DOCKER_CONFIG="$WORKSPACE/.docker"
          mkdir -p "$DOCKER_CONFIG/cli-plugins"
          if [ ! -x "$DOCKER_CONFIG/cli-plugins/docker-compose" ]; then
            echo "Lade docker compose v2.29.7…"
            curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
              -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
            chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
          fi

          docker compose version

          # DEV hochfahren
          test -f docker-compose.yml
          docker compose -f docker-compose.yml up -d

          # Kurze Logs
          docker compose -f docker-compose.yml logs --tail=50 odoo || true
        '''
      }
    }

    stage('Smoke DEV') {
      steps {
        sh '''
          set -eux
          ./scripts/smoke_dev.sh
        '''
      }
    }

    stage('Deploy QS') {
      steps {
        sh '''
          set -eux

          # Compose v2 steht bereits bereit (siehe DEV-Stage)

          # QS hochfahren
          test -f docker-compose.qs.yml
          docker compose -f docker-compose.qs.yml up -d

          # Kurze Logs
          docker compose -f docker-compose.qs.yml logs --tail=50 odoo_qs || true

          # Optional: Warte auf DB-Healthy (nur falls Healthcheck in db_qs definiert ist)
          # sleep 5
        '''
      }
    }

    stage('Smoke QS') {
      steps {
        sh '''
          set -eux
          # Standard prüft /web/login; falls deine QS-DB nicht initialisiert ist:
          # QS_URL="http://localhost:8069/web/database/selector" ./scripts/smoke_qs.sh
          ./scripts/smoke_qs.sh
        '''
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: '**/*.log,**/*.txt,**/*.out,**/*.json', allowEmptyArchive: true
    }
  }
}
