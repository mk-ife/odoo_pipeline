pipeline {
  agent any

  options {
    timestamps()
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
          docker.withRegistry('', null) {
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
    }

    stage('Build (optional)') {
      when { expression { return fileExists('Dockerfile') } }
      steps {
        sh '''
          set -eux
          docker build -t test-odoo .
        '''
      }
    }

    /* ===================== DEV ===================== */
    stage('Deploy DEV') {
      steps {
        sh '''
          set -eux
          echo "Workspace: $WORKSPACE"
          export DOCKER_CONFIG="$WORKSPACE/.docker"
          mkdir -p "$DOCKER_CONFIG/cli-plugins"
          # docker compose v2 ist bereits installiert (Deploy-Setup), aber wir prüfen:
          docker compose version

          test -f docker-compose.yml
          docker compose -f docker-compose.yml up -d

          # kurze Log-Sicht auf odoo
          docker compose -f docker-compose.yml logs --tail=50 odoo || true
        '''
      }
    }

    stage('Init DB DEV') {
      steps {
        sh '''
          set -eux
          # Warte bis Postgres gesund ist
          for i in $(seq 1 30); do
            if docker compose -f docker-compose.yml exec -T db sh -lc "pg_isready -U odoo -d odoo18" ; then
              echo "Postgres ist bereit"
              break
            fi
            echo "Warte auf Postgres (${i}/30)…"
            sleep 2
          done

          # Initialisiere einmalig die DB mit 'base'
          # --stop-after-init sorgt dafür, dass nur init ausgeführt wird
          docker compose -f docker-compose.yml exec -T odoo sh -lc "odoo -d odoo18 -i base --without-demo=all --stop-after-init || true"
        '''
      }
    }

    stage('Smoke DEV') {
      steps {
        sh '''
          set -eux
          ./scripts/smoke_dev.sh
        '''
      }
    }

    /* ===================== QS ===================== */
    stage('Deploy QS') {
      steps {
        sh '''
          set -eux
          export DOCKER_CONFIG="$WORKSPACE/.docker"
          mkdir -p "$DOCKER_CONFIG/cli-plugins"
          docker compose version

          test -f docker-compose.qs.yml
          docker compose -f docker-compose.qs.yml up -d

          docker compose -f docker-compose.qs.yml logs --tail=50 odoo_qs || true
        '''
      }
    }

    stage('Smoke QS') {
      steps {
        sh '''
          set -eux
          ./scripts/smoke_qs.sh
        '''
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: '**/smoke_*.log', onlyIfSuccessful: false
    }
  }
}
