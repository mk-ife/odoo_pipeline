pipeline {
  agent any
  environment {
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
    QS_COMPOSE    = "docker-compose.qs.yml"
    QS_PROJECT    = "odoo-pipeline-qs"
    QS_SMOKE_URL  = "http://localhost:18069/web/login"
    QS_SMOKE_ALT  = "http://localhost:18069/web/database/selector"
  }

  stages {
    stage('Checkout') { steps { checkout scm } }

    stage('Setup Docker Compose') {
      steps {
        sh '''
          set -eux
          mkdir -p "$DOCKER_CONFIG/cli-plugins"
          if [ ! -x "$DOCKER_CONFIG/cli-plugins/docker-compose" ]; then
            echo "Installing docker compose v2.29.7..."
            curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
              -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
            chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
          fi
          docker compose version
        '''
      }
    }

    stage('Deploy (QS)') {
      steps {
        sh '''
          set -eux
          # QS-Config-Datei sicherstellen (nicht überschreiben, wenn sie schon da ist)
          mkdir -p config_qs
          [ -d config_qs/odoo.conf ] && rm -rf config_qs/odoo.conf
          [ -s config_qs/odoo.conf ] || cat > config_qs/odoo.conf <<CONF
[options]
addons_path = /mnt/extra-addons
data_dir    = /var/lib/odoo
db_host     = db_qs
db_port     = 5432
db_user     = odoo
db_password = password
admin_passwd = admin123
# db_name = odoo18_qs
CONF

          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" down --remove-orphans || true
          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" up -d

          echo "Warte auf Postgres (QS/db_qs)…"
          for i in $(seq 1 90); do
            if docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" exec -T db_qs sh -lc \
              'command -v pg_isready >/dev/null 2>&1 || exit 99; pg_isready -h 127.0.0.1 -U "${POSTGRES_USER:-odoo}" -d "${POSTGRES_DB:-odoo18_qs}"'; then
              echo "Postgres QS ready."; break
            else
              echo "DB QS noch nicht bereit ($i/90)…"; sleep 2
            fi
          done

          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" logs --no-color --tail=120 db_qs || true
          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" logs --no-color --tail=120 odoo_qs || true
        '''
      }
    }

    stage('Init DB (QS)') {
      steps {
        sh '''
          set -eux
          # Einmalige Initialisierung (EntryPoint umgehen)
          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" run --rm \
            --entrypoint odoo \
            odoo_qs -c /etc/odoo/odoo.conf \
                    -d odoo18_qs \
                    -i base \
                    --without-demo=all \
                    --stop-after-init || true

          docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" up -d
        '''
      }
    }

    stage('Smoke (QS)') {
      steps {
        sh '''
          set -eux
          echo "Smoke-Test QS…"
          for i in $(seq 1 90); do
            if docker compose -f "${QS_COMPOSE}" -p "${QS_PROJECT}" exec -T \
              -e SMOKE_URL="${QS_SMOKE_URL}" -e SMOKE_ALT="${QS_SMOKE_ALT}" \
              odoo_qs python3 - <<'PY'
import os, urllib.request, sys
urls = [u for u in (os.environ.get("SMOKE_URL"), os.environ.get("SMOKE_ALT")) if u]
def ok(u):
    try:
        with urllib.request.urlopen(u, timeout=5) as r:
            body = r.read(4000).lower()
            good = (r.status == 200) and any(k in body for k in (b"odoo", b"login", b"database", b"selector"))
            print("URL:", u, "HTTP:", r.status, "LEN:", len(body))
            return good
    except Exception as e:
        print("URL:", u, "ERR:", e); return False
sys.exit(0 if any(ok(u) for u in urls) else 1)
PY
            then
              echo "Smoke QS OK"; break
            else
              echo "Warte auf Odoo QS ($i/90)…"; sleep 3
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
      archiveArtifacts artifacts: '**/docker-compose.qs.yml, **/Jenkinsfile.qs', onlyIfSuccessful: false
    }
  }
}
