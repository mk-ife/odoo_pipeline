pipeline {
  agent any
  environment {
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
  }
  stages {
    stage('Checkout QS') {
      steps { checkout scm }
    }

    stage('Deploy QS') {
      steps {
        sh '''
          set -eux
          echo "Workspace: $PWD"

          # docker compose v2 im Jenkins-Context bereitstellen (falls nicht vorhanden)
          mkdir -p "$DOCKER_CONFIG/cli-plugins"
          if [ ! -x "$DOCKER_CONFIG/cli-plugins/docker-compose" ]; then
            echo "Lade docker compose v2.29.7…"
            curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
            chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
          fi
          docker compose version

          # Sicherstellen, dass die QS-Config vorhanden ist (odoo.conf im Verzeichnis)
          mkdir -p config/qs
          [ -f config/qs/odoo.conf ] || cat > config/qs/odoo.conf <<CONF
[options]
addons_path = /mnt/extra-addons
data_dir    = /var/lib/odoo
db_host     = db
db_port     = 5432
db_user     = odoo
db_password = password
# optional:
# admin_passwd = admin123
# db_name      = odoo_qs
CONF

          # QS-Stack neu starten
          docker compose -f docker-compose.qs.yml -p odoo-qs down --remove-orphans || true
          docker compose -f docker-compose.qs.yml -p odoo-qs up -d

          # Debug: Zeig die Config im Container (wichtig, um Mount zu verifizieren)
          docker compose -f docker-compose.qs.yml -p odoo-qs exec -T odoo sh -lc '
            echo "=== Container: /etc/odoo Inhalt ===";
            ls -la /etc/odoo || true;
            echo "=== /etc/odoo/odoo.conf (Head) ===";
            [ -f /etc/odoo/odoo.conf ] && head -n 80 /etc/odoo/odoo.conf || echo "odoo.conf fehlt";
          '

          # DB-Logs und Odoo-Logs kurz anzeigen (letzte Zeilen)
          docker compose -f docker-compose.qs.yml -p odoo-qs logs --tail=50 db || true
          docker compose -f docker-compose.qs.yml -p odoo-qs logs --tail=50 odoo || true
        '''
      }
    }

    stage('Init QS DB (base)') {
      steps {
        sh '''
          set -eux
          echo "Initialisiere QS-DB (Install base ohne Demo)…"

          # DB muss healthy sein
          i=0
          until [ "$i" -ge 60 ]; do
            if docker compose -f docker-compose.qs.yml -p odoo-qs ps --services --filter "status=running" | grep -q "^db$"; then
              break
            fi
            i=$((i+1))
            echo "Warte auf laufenden DB-Container ($i/60)…"
            sleep 2
          done

          # WARUM: Beim direkten 'odoo' Aufruf liest Odoo im Exec nicht immer die System-Config.
          # Daher DB-Parameter EXPLIZIT mitgeben:
          docker compose -f docker-compose.qs.yml -p odoo-qs exec -T odoo \
            odoo \
              -d odoo_qs \
              -i base \
              --without-demo=all \
              --db_host=db \
              --db_port=5432 \
              --db_user=odoo \
              --db_password=password \
              --stop-after-init || true

          # kurze Pause
          sleep 3

          # Noch einmal Odoo-Log zeigen
          docker compose -f docker-compose.qs.yml -p odoo-qs logs --tail=80 odoo || true
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
URLS = ["http://localhost:8069/web/database/selector", "http://localhost:8069/web/login"]
ok = False
for url in URLS:
    try:
        with urllib.request.urlopen(url, timeout=2) as r:
            body = r.read(2000)
            ok = (r.status == 200) and (b"odoo" in body.lower() or b"login" in body.lower() or b"database" in body.lower())
            print("TRY:", url, "HTTP:", r.status, "LEN:", len(body))
            if ok:
                break
    except Exception as e:
        print("TRY:", url, "ERR:", e)
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
      archiveArtifacts artifacts: '**/docker-compose.qs.yml, **/Jenkinsfile.qs, config/qs/odoo.conf', onlyIfSuccessful: false
    }
  }
}
