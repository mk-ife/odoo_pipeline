pipeline {
  agent any
  environment {
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
  }
  stages {

    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Deploy QS') {
      steps {
        sh '''
          set -eux
          echo "Workspace: $PWD"

          mkdir -p "$DOCKER_CONFIG/cli-plugins"
          [ -x "$DOCKER_CONFIG/cli-plugins/docker-compose" ] || {
            echo "Lade docker compose v2.29.7…"
            curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
            chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
          }
          docker compose version

          # Clean & Up (QS)
          docker compose -f docker-compose.qs.yml -p odoo-qs down --remove-orphans || true
          docker compose -f docker-compose.qs.yml -p odoo-qs up -d

          # DB healthy abwarten
          for i in $(seq 1 60); do
            if docker compose -f docker-compose.qs.yml -p odoo-qs ps --services --filter status=running | grep -q '^db$'; then
              if docker compose -f docker-compose.qs.yml -p odoo-qs logs --tail=10 db | grep -qi "ready to accept connections"; then
                echo "QS DB ready."
                break
              fi
            fi
            echo "Warte auf QS DB ($i/60)…"
            sleep 2
          done

          # Odoo running abwarten (kein Restarting)
          OD=$(docker compose -f docker-compose.qs.yml -p odoo-qs ps -q odoo)
          for i in $(seq 1 60); do
            st=$(docker inspect -f '{{.State.Status}}' "$OD" || true)
            rs=$(docker inspect -f '{{.State.Restarting}}' "$OD" || true)
            echo "Odoo state=$st restarting=$rs"
            [ "$st" = "running" ] && [ "$rs" != "true" ] && break || true
            echo "Warte auf Odoo QS Container ($i/60)…"
            sleep 2
          done

          docker compose -f docker-compose.qs.yml -p odoo-qs logs --tail=50 db || true
          docker compose -f docker-compose.qs.yml -p odoo-qs logs --tail=50 odoo || true
        '''
      }
    }

    stage('Init QS DB (base)') {
      steps {
        sh '''
          set -eux
          echo "Initialisiere QS-DB (Install base ohne Demo, per CLI-DB-Parameter)…"

          OD=$(docker compose -f docker-compose.qs.yml -p odoo-qs ps -q odoo)

          # kleine Wartezeit nach Start
          sleep 5

          # Die ENV (HOST, PORT, USER, PASSWORD) sind im Container vorhanden
          for retry in $(seq 1 10); do
            if docker exec -i "$OD" \
              bash -lc 'exec odoo -d "$DATABASE" -i base --without-demo=all --stop-after-init --db_host="$HOST" --db_port="$PORT" --db_user="$USER" --db_password="$PASSWORD"'
            then
              echo "QS DB init OK"
              break
            else
              echo "Init QS DB Versuch $retry/10 gescheitert – warte und versuche erneut…"
              sleep 3
            fi
          done

          docker compose -f docker-compose.qs.yml -p odoo-qs logs --tail=80 odoo || true
        '''
      }
    }

    stage('Smoke QS') {
      steps {
        sh '''
          set -eux
          echo "Smoke-Test QS (im Odoo-Container, http://localhost:8069)…"

          OD=$(docker compose -f docker-compose.qs.yml -p odoo-qs ps -q odoo)

          for i in $(seq 1 60); do
            if docker exec -i "$OD" \
              python3 - <<'PY'
import urllib.request, sys
def try_url(u):
    try:
        with urllib.request.urlopen(u, timeout=2) as r:
            b = r.read(2000)
            ok = (r.status in (200, 302, 303)) and any(k in b.lower() for k in [b"odoo", b"login", b"database"])
            print("OK:", u, "HTTP", r.status, "LEN", len(b))
            return ok
    except Exception as e:
        print("TRY:", u, "ERR:", e)
        return False

ok = try_url("http://localhost:8069/web/database/selector") or try_url("http://localhost:8069/web/login")
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
    always {
      archiveArtifacts artifacts: '**/docker-compose*.yml, **/Jenkinsfile, config/**/*.conf', onlyIfSuccessful: false
    }
  }
}
