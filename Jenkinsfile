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
          echo "Smoke-Test DEV (im Odoo-Container mit Python)…"
          for i in $(seq 1 60); do
            if docker compose -f docker-compose.yml -p odoo-pipeline exec -T odoo \
              python3 - <<'PY'
import urllib.request, sys
urls = [
    "http://localhost:8069/web/database/selector",  # erreichbar, wenn DB noch nicht init/gewählt
    "http://localhost:8069/web/login",              # erreichbar, wenn DB vorhanden/aktiv
]
ok = False
for u in urls:
    try:
        with urllib.request.urlopen(u, timeout=3) as r:
            if r.status == 200:
                print("OK:", u, "HTTP", r.status)
                ok = True
                break
    except Exception as e:
        print("TRY:", u, "ERR:", e)
sys.exit(0 if ok else 1)
PY
            then
              echo "Smoke DEV OK"
              break
            else
              echo "Warte auf Odoo DEV ($i/60)…"
              sleep 3
            fi
          done
        '''
      }
    }

    /* ===================== QS (neu) ===================== */
    stage('Deploy QS') {
      steps {
        sh '''
          set -eux
          echo "Deploy QS…"

          mkdir -p config
          [ -f config/odoo_qs.conf ] || cat > config/odoo_qs.conf <<CONF
[options]
addons_path = /mnt/extra-addons
data_dir    = /var/lib/odoo
db_host     = db_qs
db_port     = 5432
db_user     = odoo
db_password = password
CONF

          docker compose -f docker-compose.qs.yml -p odoo-pipeline-qs down --remove-orphans || true
          docker compose -f docker-compose.qs.yml -p odoo-pipeline-qs up -d

          docker compose -f docker-compose.qs.yml -p odoo-pipeline-qs logs --no-color --tail=50 db_qs || true
          docker compose -f docker-compose.qs.yml -p odoo-pipeline-qs logs --no-color --tail=50 odoo_qs || true
        '''
      }
    }
    stage('Smoke QS') {
      steps {
        sh '''
          set -eux
          echo "Smoke-Test QS (im Odoo-QS-Container mit Python)…"
          for i in $(seq 1 60); do
            if docker compose -f docker-compose.qs.yml -p odoo-pipeline-qs exec -T odoo_qs \
              python3 - <<'PY'
import urllib.request, sys
urls = [
    "http://localhost:8069/web/database/selector",
    "http://localhost:8069/web/login",
]
ok = False
for u in urls:
    try:
        with urllib.request.urlopen(u, timeout=3) as r:
            if r.status == 200:
                print("OK:", u, "HTTP", r.status)
                ok = True
                break
    except Exception as e:
        print("TRY:", u, "ERR:", e)
sys.exit(0 if ok else 1)
PY
            then
              echo "Smoke QS OK"
              break
            else
              echo "Warte auf Odoo QS ($i/60)…"
              sleep 3
            fi
          done
        '''
      }
    }
  }
  post {
    always { archiveArtifacts artifacts: '**/docker-compose*.yml, **/Jenkinsfile', onlyIfSuccessful: false }
  }
}
