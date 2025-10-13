#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="${WORKSPACE:-$(pwd)}"
export DOCKER_CONFIG="$WORKSPACE/.docker"
mkdir -p "$DOCKER_CONFIG/cli-plugins"

if ! docker compose version >/dev/null 2>&1; then
  echo "Lade docker compose v2.29.7…"
  curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
    -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
  chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
fi

FILE="docker-compose.qs.yml"
SVC="odoo_qs"
URL="${QS_URL:-http://localhost:8069/web/login}"
RETRIES="${RETRIES:-60}"
SLEEP_SECS="${SLEEP_SECS:-3}"

test -f "$FILE"
docker compose -f "$FILE" ps "$SVC" >/dev/null

echo "Smoke-Test QS: warte bis $URL im Container $SVC erreichbar ist (${RETRIES} Versuche, alle ${SLEEP_SECS}s)…"
for i in $(seq 1 "$RETRIES"); do
  if docker compose -f "$FILE" exec -T "$SVC" sh -lc "curl -fsS '$URL' >/dev/null"; then
    echo "Smoke QS OK: $URL erreichbar"
    exit 0
  fi
  echo "Warte auf Odoo QS (${i}/${RETRIES})…"
  sleep "$SLEEP_SECS"
done

echo "Smoke-Test QS fehlgeschlagen"
exit 1
