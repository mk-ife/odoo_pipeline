pipeline {
  agent any

  environment {
    DOCKER_CONFIG = "${WORKSPACE}/.docker"

    // ==== DEV ====
    DEV_COMPOSE   = "docker-compose.yml"
    DEV_PROJECT   = "odoo-pipeline"
    DEV_PORT      = "8069"
    DEV_SMOKE_URL = "http://localhost:8069/web/login"
    DEV_SMOKE_ALT = "http://localhost:8069/web/database/selector"

    // ==== QS ====
    // Wir erwarten eine separate QS-Compose mit Services 'odoo_qs' und 'db_qs'
    QS_COMPOSE    = "docker-compose.qs.yml"
    QS_PROJECT    = "odoo-pipeline-qs"
    QS_PORT       = "18069"
    QS_SMOKE_URL  = "http://localhost:18069/web/login"
    QS_SMOKE_ALT  = "http://localhost:18069/web/database/selector"
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

    // ===== DEV =====
    stage('Deploy (DEV)') {
      steps {
        sh '''
          set -eux

          # einfache DEV-Config, falls gebraucht
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

          docker compose -f "${DEV_COMPOSE}" -p "${DEV_PROJECT}" down --remove-orphans || true
          docker compose -f "${DEV_COMPOSE}" -p "${DEV_PROJECT}" up -d

          echo "Warte auf Postgres (DEV/db)…"
          for i in $(seq 1 60); do
            if docker compose -f "${DEV_COMPOSE}" -p "${DEV_PROJECT}" exec -T db sh -lc 'command -v pg_isready >/dev/null 2>&1 || exit 99; pg_isready -h 127.0.0.1 -U "$${POSTGRES_USER:-odoo}" -d "$${POSTGRES_DB:-postgres}"'; then
              echo "Postgres DEV ready."
              break
            else
              echo "DB DEV noch nicht bereit ($i/60)…"
              sleep 2
            fi
          done

          docker compose -f "${DEV_COMPOSE}" -p "${DEV_PROJECT}" logs --no-color --tail=80 db || true
          docker compose -f "${DEV_COMPOSE}" -p "${DEV_PROJECT}" logs --no-color --tail=80 odoo || true
        '''
      }
    }

    stage('Smoke (DEV)') {
      steps {
        sh '''
          set -eux
          echo "Smoke-Test DEV…"

          for i in $(seq 1 60); do
            if docker compose -f "${DEV_COMPOSE}" -p "${DEV_PROJECT}" exec -T odoo python3 - <<'PY'
import urllib.request, sys
urls = [
    "${DEV_SMOKE_URL}",
    "${DEV_SMOKE_ALT}",
]
def ok(u):
    try:
        with urllib.request.urlopen(u, timeout=3) as r:
            body = r.read(2000).lower()
            good = (r.status == 200) and (b"odoo" in body or b"login" in body or b"database" in body or b"selector" in body)
            print("URL:", u, "HTTP:", r.status, "LEN:", len(body))
            return good
    except Exception as e:
        print("URL:", u, "ERR:", e)
        return False
sys.exit(0 if any(ok(u) for u in urls) else 1)
PY
            then
              echo "Smoke DEV OK"
              break
            else
              echo "Warte auf Odoo DEV ($i/60)…"
              sleep 3
            fi
          done

          docker compose -f "${DEV_COMPOSE}" -p "${DEV_PROJECT}" logs --no-color --since=3m odoo || true
          docker compose -f "${DEV_COMPOSE}" -p "${DEV_PROJECT}" logs --no-color --since=3m db || true
        '''
      }
    }

    // ===== QS =====
    stage('Deploy (QS)') {
      when {
        expression { return fileExists(env.QS_COMPOSE) }
      }
      steps {
        sh '''
          set -eux
          echo "Deploy QS…"

          # optionale QS-Config nur anlegen, falls nicht vorhanden
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

          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" down --remove-orphans || true
          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" up -d

          echo "Warte auf Postgres (QS/db_qs)…"
          for i in $(seq 1 90); do
            if docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" exec -T db_qs sh -lc 'command -v pg_isready >/dev/null 2>&1 || exit 99; pg_isready -h 127.0.0.1 -U "$${POSTGRES_USER:-odoo}" -d "$${POSTGRES_DB:-postgres}"'; then
              echo "Postgres QS ready."
              break
            else
              echo "DB QS noch nicht bereit ($i/90)…"
              sleep 2
            fi
          done

          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" logs --no-color --tail=120 db_qs || true
          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" logs --no-color --tail=120 odoo_qs || true
        '''
      }
    }

    stage('Smoke (QS Gate)') {
      when {
        expression { return fileExists(env.QS_COMPOSE) }
      }
      steps {
        sh '''
          set -eux
          echo "Smoke-Test QS…"

          for i in $(seq 1 90); do
            if docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" exec -T odoo_qs python3 - <<'PY'
import urllib.request, sys
urls = [
    "${QS_SMOKE_URL}",
    "${QS_SMOKE_ALT}",
]
def ok(u):
    try:
        with urllib.request.urlopen(u, timeout=4) as r:
            body = r.read(4000).lower()
            good = (r.status == 200) and (b"odoo" in body or b"login" in body or b"database" in body or b"selector" in body)
            print("URL:", u, "HTTP:", r.status, "LEN:", len(body))
            return good
    except Exception as e:
        print("URL:", u, "ERR:", e)
        return False
sys.exit(0 if any(ok(u) for u in urls) else 1)
PY
            then
              echo "Smoke QS OK"
              break
            else
              echo "Warte auf Odoo QS ($i/90)…"
              sleep 3
            fi
          done

          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" logs --no-color --since=5m odoo_qs || true
          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" logs --no-color --since=5m db_qs || true
        '''
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: '**/docker-compose*.yml, **/Jenkinsfile', onlyIfSuccessful: false
    }
    failure {
      echo 'Pipeline fehlgeschlagen – bitte Logs oben prüfen.'
    }
  }
}
