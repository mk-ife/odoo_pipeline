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
          // als root, damit pip schreiben darf (Permission-Issue vermeiden)
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
          # Optional: falls kein Dockerfile existiert, Build überspringen
          docker build -t test-odoo . || echo "kein Dockerfile gefunden – überspringe Build"
        '''
      }
    }

    stage('Deploy') {
      steps {
        sh '''
          # Compose-CLI per Container (keine lokale Installation nötig)
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v "$PWD:$PWD" -w "$PWD" \
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
