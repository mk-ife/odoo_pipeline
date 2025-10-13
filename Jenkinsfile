pipeline {
  agent any
  options { timestamps() }
  parameters {
    booleanParam(name: 'DEPLOY_QS', defaultValue: false, description: 'Auch nach QS deployen & Smoke-Test ausführen')
  }
  environment {
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
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

    stage('Deploy (DEV)') {
      steps {
        sh '''
          set -eux
          echo "Workspace: $PWD"

          # docker compose v2 (CLI-Plugin) bereitstellen (einmalig pro Workspace)
          mkdir -p "${DOCKER_CONFIG}/cli-plugins"
          if [ ! -x "${DOCKER_CONFIG}/cli-plugins/docker-compose" ]; then
            echo "Lade docker compose v2.29.7…"
            curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
              -o "${DOCKER_CONFIG}/cli-plugins/docker-compose"
            chmod +x "${DOCKER_CONFIG}/cli-plugins/docker-compose"
          fi

          # Dev-Stack starten (nutzt dein bestehendes docker-compose.yml)
          test -f docker-compose.yml
          docker compose -f docker-compose.yml up -d

          # Kurz Logauszug vom Odoo-Dev
          docker compose logs --no-color --tail=50 odoo || true
        '''
      }
    }

    stage('Smoke (DEV)') {
      steps {
        sh '''
          set -eux
          echo "Smoke-Test: warte bis Odoo (DEV) antwortet…"
          for i in $(seq 1 30); do
            if docker compose exec -T odoo curl -fsS http://localhost:8069/web/login >/dev/null 2>&1; then
              echo "OK: DEV Odoo antwortet."
              exit 0
            fi
            echo "Warte auf Odoo DEV (${i}/30)…"
            sleep 3
          done
          echo "Smoke-Test DEV fehlgeschlagen"
          exit 1
        '''
      }
    }

    stage('Deploy (QS)') {
      when { expression { return params.DEPLOY_QS } }
      steps {
        sh '''
          set -eux

          # docker compose v2 (CLI-Plugin) ist bereits im DEV-Step bereitgestellt
          # QS-Stack: eigene Datei, andere Ports/Volumes/Namen
          test -f docker-compose.qs.yml
          docker compose -f docker-compose.qs.yml up -d

          # DB warten via Healthcheck (compose macht das schon beim Start),
          # Wir geben trotzdem Logs aus:
          docker compose -f docker-compose.qs.yml logs --no-color --tail=80 db_qs || true
          docker compose -f docker-compose.qs.yml ps
        '''
      }
    }

    stage('Smoke (QS)') {
      when { expression { return params.DEPLOY_QS } }
      steps {
        sh '''
          set -eux
          echo "Smoke-Test QS: warte bis Odoo (QS) antwortet…"
          for i in $(seq 1 30); do
            if docker compose -f docker-compose.qs.yml exec -T odoo_qs curl -fsS http://localhost:8069/web/login >/dev/null 2>&1; then
              echo "OK: QS Odoo antwortet."
              exit 0
            fi
            echo "Warte auf Odoo QS (${i}/30)…"
            sleep 3
          done
          echo "Smoke-Test QS fehlgeschlagen"
          exit 1
        '''
      }
    }
  }
  post {
    always {
      archiveArtifacts artifacts: '**/*.log, **/compose*.txt', onlyIfSuccessful: false
    }
  }
}
