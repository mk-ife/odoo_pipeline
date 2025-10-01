pipeline {
  agent any
  options { timestamps() }
  environment {
    COMPOSE_FILE = 'docker-compose.yml'
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Lint') {
      agent {
        docker {
          image 'python:3.11-slim'
          args '-u 0 -e PIP_DISABLE_PIP_VERSION_CHECK=1'
        }
      }
      steps {
        sh '''
          python --version
          pip install --no-cache-dir -q flake8
          flake8 .
        '''
      }
    }

    stage('Build') {
      steps {
        sh '''
          docker build -t test-odoo . || echo "kein Dockerfile gefunden – überspringe Build"
        '''
      }
    }

    stage('Deploy') {
      steps {
        sh '''
          echo "WORKSPACE=$WORKSPACE"
          echo "COMPOSE_FILE=$COMPOSE_FILE"
          # Sicherstellen, dass die Compose-Datei wirklich da ist:
          test -f "$WORKSPACE/$COMPOSE_FILE" || { 
            echo "Compose-Datei nicht gefunden unter: $WORKSPACE/$COMPOSE_FILE";
            echo "Inhalt von $WORKSPACE:"; ls -la "$WORKSPACE"; 
            exit 1; 
          }

          # Compose-CLI per Container (nur Docker-Socket + Workspace nötig)
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v "$WORKSPACE:$WORKSPACE" -w "$WORKSPACE" \
            docker/compose:latest up -d
        '''
      }
    }

    stage('Smoke') {
      steps {
        sh '''
          # Warte bis zu 180s, bis Odoo /web/login liefert
          for i in $(seq 1 90); do
            docker run --rm --network host curlimages/curl:8.9.1 \
              -fsS http://localhost:8069/web/login >/dev/null && {
                echo "Smoke OK"; exit 0; }
            sleep 2
          done
          echo "Smoke failed"; exit 1
        '''
      }
    }
  }
}
