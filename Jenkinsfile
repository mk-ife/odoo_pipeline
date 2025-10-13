pipeline {
  agent any

  environment {
    DOCKER_CONFIG = "${WORKSPACE}/.docker"

    // ==== DEV ====
    DEV_COMPOSE   = "docker-compose.yml"
    DEV_PROJECT   = "odoo-pipeline"
    DEV_SMOKE_URL = "http://localhost:8069/web/login"
    DEV_SMOKE_ALT = "http://localhost:8069/web/database/selector"

    // Stabiler Compose-Tag
    ODOO_IMAGE    = "odoo-custom:latest"

    // ==== QS optional ====
    QS_COMPOSE    = "docker-compose.qs.yml"
    QS_PROJECT    = "odoo-pipeline-qs"
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

    stage('Build Image (optional)') {
      steps {
        sh '''
          set -eux
          if [ -f Dockerfile ]; then
            DOCKER_BUILDKIT=1 docker build -t "odoo-custom:${BUILD_NUMBER}" .
            docker tag "odoo-custom:${BUILD_NUMBER}" "odoo-custom:latest"
          else
            echo "Kein Dockerfile – Build übersprungen (Deploy nutzt Fallback, falls Image fehlt)."
          fi
          docker image ls | grep -E '^odoo-custom\\s' || true
        '''
      }
    }

    stage('Deploy (DEV)') {
      steps {
        sh '''
          set -eux
          mkdir -p config
          [ -s config/odoo.conf ] || cat > config/odoo.conf <<CONF
[options]
addons_path = /mnt/extra-addons
data_dir    = /var/lib/odoo
db_host     = db
db_port     = 5432
db_user     = odoo
db_password = password
CONF

          # WICHTIG: Fallback, falls lokales Image fehlt:
          if ! docker image inspect "${ODOO_IMAGE}" >/dev/null 2>&1; then
            echo "Lokales Image ${ODOO_IMAGE} fehlt – ziehe Fallback 'odoo:18' und tagge es…"
            docker pull odoo:18
            docker tag odoo:18 "${ODOO_IMAGE}"
          fi

          docker compose -f "${DEV_COMPOSE}" -p "${DEV_PROJECT}" down --remove-orphans || true
          ODOO_IMAGE="${ODOO_IMAGE}" docker compose -f "${DEV_COMPOSE}" -p "${DEV_PROJECT}" up -d --force-recreate --no-build --pull never

          echo "Warte auf Postgres (DEV/db)…"
          for i in $(seq 1 60); do
            if docker compose -f "${DEV_COMPOSE}" -p "${DEV_PROJECT}" exec -T db sh -lc 'command -v pg_isready >/dev/null 2>&1 || exit 99; pg_isready -h 127.0.0.1 -U "\${POSTGRES_USER:-odoo}" -d "\${POSTGRES_DB:-postgres}"'; then
              echo "Postgres DEV ready."
              break
            else
              echo "DB DEV noch nicht bereit ($i/60)…"
              sleep 2
            fi
          done

          docker compose -f "${DEV_COMPOSE}" -p "${DEV_PROJECT}" logs --no-color --tail=160 db || true
          docker compose -f "${DEV_COMPOSE}" -p "${DEV_PROJECT}" logs --no-color --tail=160 odoo || true
        '''
      }
    }

    stage('Smoke (DEV)') {
      steps {
        sh '''
          set -eux
          echo "Smoke-Test DEV…"
          for i in $(seq 1 60); do
            if docker compose -f "${DEV_COMPOSE}" -p "${DEV_PROJECT}" exec -T \
              -e SMOKE_URL="${DEV_SMOKE_URL}" -e SMOKE_ALT="${DEV_SMOKE_ALT}" \
              odoo python3 - <<'PY'
import os, urllib.request, sys
urls = [u for u in [os.environ.get("SMOKE_URL"), os.environ.get("SMOKE_ALT")] if u]
def ok(u):
    try:
        with urllib.request.urlopen(u, timeout=4) as r:
            body = r.read(4000).lower()
            good = (r.status == 200) and any(k in body for k in (b"odoo", b"login", b"database", b"selector"))
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

          docker compose -f "${DEV_COMPOSE}" -p "${DEV_PROJECT}" logs --no-color --since=5m odoo || true
          docker compose -f "${DEV_COMPOSE}" -p "${DEV_PROJECT}" logs --no-color --since=5m db || true
        '''
      }
    }

    // ===== QS (nur falls Datei existiert) =====
    stage('Deploy (QS)') {
      when { expression { return fileExists(env.QS_COMPOSE) } }
      steps {
        sh '''
          set -eux
          # Fallback-Image auch für QS bereitstellen (odoo_qs benutzt eigenes Compose)
          if ! docker image inspect "${ODOO_IMAGE}" >/dev/null 2>&1; then
            docker pull odoo:18
            docker tag odoo:18 "${ODOO_IMAGE}"
          fi

          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" down --remove-orphans || true
          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" up -d --force-recreate --no-build --pull never

          echo "Warte auf Postgres (QS/db_qs)…"
          for i in $(seq 1 90); do
            if docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" exec -T db_qs sh -lc 'command -v pg_isready >/dev/null 2>&1 || exit 99; pg_isready -h 127.0.0.1 -U "\${POSTGRES_USER:-odoo}" -d "\${POSTGRES_DB:-postgres}"'; then
              echo "Postgres QS ready."
              break
            else
              echo "DB QS noch nicht bereit ($i/90)…"
              sleep 2
            fi
          done

          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" logs --no-color --tail=200 db_qs || true
          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" logs --no-color --tail=200 odoo_qs || true
        '''
      }
    }

    stage('Smoke (QS Gate)') {
      when { expression { return fileExists(env.QS_COMPOSE) } }
      steps {
        sh '''
          set -eux
          for i in $(seq 1 90); do
            if docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" exec -T \
              -e SMOKE_URL="${QS_SMOKE_URL}" -e SMOKE_ALT="${QS_SMOKE_ALT}" \
              odoo_qs python3 - <<'PY'
import os, urllib.request, sys
urls = [u for u in [os.environ.get("SMOKE_URL"), os.environ.get("SMOKE_ALT")] if u]
def ok(u):
    try:
        with urllib.request.urlopen(u, timeout=5) as r:
            body = r.read(4000).lower()
            good = (r.status == 200) and any(k in body for k in (b"odoo", b"login", b"database", b"selector"))
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

          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" logs --no-color --since=7m odoo_qs || true
          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" logs --no-color --since=7m db_qs || true
        '''
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: '**/docker-compose*.yml, **/Jenkinsfile', onlyIfSuccessful: false
    }
  }
}
