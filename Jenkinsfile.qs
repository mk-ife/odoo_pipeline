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

    stage('Deploy QS') {
      steps {
        sh '''
          set -eux
          echo "Workspace: $PWD"

          # QS Compose (separat) starten – eigenes Projektlabel
          test -f docker-compose.qs.yml

          # Sauber aufräumen und neu starten
          docker compose -f docker-compose.qs.yml -p odoo-qs down --remove-orphans || true
          docker compose -f docker-compose.qs.yml -p odoo-qs up -d

          # Logs anzeigen (nur Tail)
          docker compose -f docker-compose.qs.yml -p odoo-qs logs --no-color --tail=50 db || true
          docker compose -f docker-compose.qs.yml -p odoo-qs logs --no-color --tail=50 odoo || true
        '''
      }
    }

    stage('Init QS DB (base)') {
      steps {
        sh '''
          set -eux
          echo "Initialisiere QS-DB (Install base ohne Demo)…"

          # Warte bis DB healthy ist (Compose-Healthcheck deckt das ab; trotzdem kurze Pause)
          sleep 5

          # Base-Modul in QS-DB initialisieren (idempotent; wenn DB schon ok ist, schnell fertig)
          docker compose -f docker-compose.qs.yml -p odoo-qs exec -T odoo \
            odoo -d odoo_qs -i base --without-demo=all --stop-after-init || true

          # Nochmals kurz warten (Odoo warm werden lassen)
          sleep 3
        '''
      }
    }

    stage('Smoke QS') {
      steps {
        sh '''
          set -eux
          echo "Smoke-Test QS (im Odoo-Container mit Python)…"
          for i in $(seq 1 60); do
            if docker compose -f docker-compose.qs.yml -p odoo-qs exec -T odoo \
              python3 - <<'PY'
import urllib.request, sys
# erst DB-Selector probieren (kommt 200 sobald Odoo lebt),
# fällt dann später auf /web/login zurück
for url in ("http://localhost:8069/web/database/selector", "http://localhost:8069/web/login"):
    try:
        with urllib.request.urlopen(url, timeout=2) as r:
            body = r.read(2000).lower()
            ok = (r.status == 200) and (b"odoo" in body or b"login" in body or b"database" in body)
            print("TRY:", url, "HTTP:", r.status, "LEN:", len(body))
            if ok:
                sys.exit(0)
    except Exception as e:
        print("TRY:", url, "ERR:", e)
sys.exit(1)
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
    always {
      archiveArtifacts artifacts: '**/docker-compose.qs.yml, **/Jenkinsfile.qs, config/odoo_qs.conf', onlyIfSuccessful: false
    }
  }
}
