pipeline {
  agent any

  environment {
    PIP_DISABLE_PIP_VERSION_CHECK = '1'
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
              pip install --no-cache-dir flake8
              flake8 .
            '''
          }
        }
      }
    }

    stage('Deploy') {
      steps {
        sh '''
          set -eux
          echo "Workspace: $PWD"

          # 1) sicherstellen, dass die Odoo-Konfig vorhanden ist
          if [ ! -f config/odoo.conf ]; then
            echo "WARN: config/odoo.conf fehlt im Workspace – lege Default an"
            mkdir -p config
            cat > config/odoo.conf <<'CONF'
[options]
addons_path = /mnt/extra-addons
data_dir = /var/lib/odoo
db_host = db
db_port = 5432
db_user = odoo
db_password = password
CONF
          fi

          # 2) docker compose v2 sicherstellen (falls nicht schon vorhanden)
          mkdir -p "$PWD/.docker/cli-plugins"
          if [ ! -x "$PWD/.docker/cli-plugins/docker-compose" ]; then
            echo "Lade docker compose v2.29.7…"
            curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
              -o "$PWD/.docker/cli-plugins/docker-compose"
            chmod +x "$PWD/.docker/cli-plugins/docker-compose"
          fi
          export DOCKER_CONFIG="$PWD/.docker"

          docker compose version

          # 3) Compose starten/aktualisieren
          test -f docker-compose.yml
          docker compose -f docker-compose.yml up -d

          # 4) kurze Logsicht
          docker compose logs --no-color --tail=50 odoo || true
        '''
      }
    }

    stage('Smoke') {
      steps {
        sh '''
          set -eux
          echo "Smoke-Test: warte bis Odoo antwortet…"
          for i in $(seq 1 30); do
            # Test läuft IM ODOO-CONTAINER
            if docker compose exec -T odoo curl -fsS http://localhost:8069/web/login >/dev/null 2>&1; then
              echo "Odoo antwortet (Versuch $i)."
              exit 0
            fi
            echo "Warte auf Odoo ($i/30)…"
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
      archiveArtifacts artifacts: '**/*.log, **/*.txt', fingerprint: false, allowEmptyArchive: true
    }
  }
}
