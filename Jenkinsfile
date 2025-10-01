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

          # Jenkins-Container-ID ermitteln (Hostname == Container-ID in Docker)
          JENKINS_CID="$(hostname)"
          echo "JENKINS_CID=$JENKINS_CID"

          # Sicht IM Compose-Container debuggen – jetzt mit --volumes-from
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --volumes-from "$JENKINS_CID" \
            -w "$WORKSPACE" \
            docker/compose:latest sh -lc '
              echo "CONTAINER PWD=$(pwd)";
              echo "CONTAINER list:"; ls -la;
              echo "Try to show docker-compose.yml:";
              [ -f docker-compose.yml ] && head -n 20 docker-compose.yml || echo "NO docker-compose.yml in container"
            '

          # Compose explizit mit -f aufrufen – jetzt sieht er die Datei
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --volumes-from "$JENKINS_CID" \
            -w "$WORKSPACE" \
            docker/compose:latest -f "$COMPOSE_FILE" up -d
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
