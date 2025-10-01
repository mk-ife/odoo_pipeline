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
      agent { docker { image 'python:3.11-slim' } }
      steps {
        sh '''
          pip install --no-cache-dir flake8
          flake8 .
        '''
      }
    }

    stage('Build') {
      steps {
        sh 'docker build -t test-odoo . || echo "kein Dockerfile gefunden – überspringe Build"'
      }
    }

    stage('Deploy') {
      steps {
        sh 'docker compose -f ${COMPOSE_FILE} up -d'
      }
    }

    stage('Smoke') {
      steps {
        sh '''
          for i in $(seq 1 30); do
            if curl -fsS http://localhost:8069/web/login >/dev/null 2>&1; then
              echo "Smoke OK"; exit 0
            fi
            sleep 2
          done
          echo "Smoke failed"; exit 1
        '''
      }
    }
  }
}
