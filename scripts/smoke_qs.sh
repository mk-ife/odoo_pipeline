#!/usr/bin/env bash
set -euo pipefail

# QS-Smoke-Test: wartet im Container odoo_qs auf erfolgreiche HTTP-Antwort.
# Standard ist /web/login (QS sollte persistent sein). Falls gewünscht:
# QS_URL="http://localhost:8069/web/database/selector" ./scripts/smoke_qs.sh

FILE="docker-compose.qs.yml"
SVC="odoo_qs"
URL="${QS_URL:-http://localhost:8069/web/login}"
RETRIES="${RETRIES:-60}"
SLEEP_SECS="${SLEEP_SECS:-3}"

# prüfe, ob Service existiert
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
