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
          echo "HOST WORKSPACE=$WORKSPACE"
          echo "HOST COMPOSE_FILE=$COMPOSE_FILE"
          test -f "$WORKSPACE/$COMPOSE_FILE" || {
            echo "Compose-Datei fehlt im HOST-Workspace: $WORKSPACE/$COMPOSE_FILE";
            ls -la "$WORKSPACE";
            exit 1;
          }

          JENKINS_CID="$(hostname)"
          echo "JENKINS_CID=$JENKINS_CID"

          # Debug: Sicht im Compose-Container
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --volumes-from "$JENKINS_CID" \
            -w "$WORKSPACE" \
            docker/compose:1.29.2 sh -lc '
              echo "PWD=$(pwd)";
              ls -la;
              echo "--- compose head ---";
              head -n 20 docker-compose.yml || true
            '

          # Compose v1 kompatibel aufrufen
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --volumes-from "$JENKINS_CID" \
            -w "$WORKSPACE" \
            docker/compose:1.29.2 -f "$COMPOSE_FILE" up -d
        '''
      }
    }

    stage('Smoke') {
      steps {
        sh '''
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
