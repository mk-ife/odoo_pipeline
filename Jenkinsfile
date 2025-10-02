pipeline {
  agent any
  environment {
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
  }
  stages {
    stage('Checkout') {
      steps { checkout scm }
    }
    stage('Lint') {
      steps {
        sh '''
          set -eux
          mkdir -p "$DOCKER_CONFIG/cli-plugins"
          [ -x "$DOCKER_CONFIG/cli-plugins/docker-compose" ] || {
            echo "Lade docker compose v2.29.7…"
            curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
            chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
          }
          docker compose version

          docker run --rm --pull=missing -u 0 -w "$PWD" \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v "$PWD:$PWD" \
            -v "$DOCKER_CONFIG:$DOCKER_CONFIG" \
            -e DOCKER_CONFIG="$DOCKER_CONFIG" \
            python:3.11-slim sh -lc '
              pip install -q flake8 && flake8 .
            '
        '''
      }
    }
    stage('Deploy') {
      steps {
        sh '''
          set -eux
          echo "Workspace: $PWD"

          mkdir -p config
          [ -f config/odoo.conf ] || cat > config/odoo.conf <<CONF
[options]
addons_path = /mnt/extra-addons
data_dir    = /var/lib/odoo
db_host     = db
db_port     = 5432
db_user     = odoo
db_password = password
CONF

          docker compose -f docker-compose.yml -p odoo-pipeline down --remove-orphans || true
          docker compose -f docker-compose.yml -p odoo-pipeline up -d

          docker compose -f docker-compose.yml -p odoo-pipeline logs --no-color --tail=50 db || true
          docker compose -f docker-compose.yml -p odoo-pipeline logs --no-color --tail=50 odoo || true
        '''
      }
    }
    stage('Smoke') {
      steps {
        sh '''
          set -eux
          echo "Smoke-Test (im Odoo-Container mit Python)…"
          for i in $(seq 1 30); do
            if docker compose -f docker-compose.yml -p odoo-pipeline exec -T odoo \
              python3 - <<'PY'
import urllib.request, sys
try:
    with urllib.request.urlopen("http://localhost:8069/web/login", timeout=2) as r:
        body = r.read(2000)
        ok = (r.status == 200) and (b"odoo" in body.lower() or b"login" in body.lower())
        print("HTTP:", r.status, "LEN:", len(body))
        sys.exit(0 if ok else 2)
except Exception as e:
    print("ERR:", e)
    sys.exit(1)
PY
            then
              echo "Smoke OK"
              break
            else
              echo "Warte auf Odoo ($i/30)…"
              sleep 3
            fi
          done
        '''
      }
    }
  }
  post {
    always { archiveArtifacts artifacts: '**/docker-compose.yml, **/Jenkinsfile', onlyIfSuccessful: false }
  }
}
