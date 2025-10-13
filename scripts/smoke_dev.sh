#!/usr/bin/env bash
set -euo pipefail

# DEV-Smoke-Test: wartet im Container "odoo" auf eine erfolgreiche HTTP-Antwort.
# Standard: /web/database/selector (funktioniert auch ohne initialisierte DB).
# Wenn du später die DB initialisiert hast, kannst du URL auch auf /web/login ändern:
#   DEV_URL="http://localhost:8069/web/login" ./scripts/smoke_dev.sh

FILE="docker-compose.yml"
SVC="odoo"
URL="${DEV_URL:-http://localhost:8069/web/database/selector}"
RETRIES="${RETRIES:-60}"
SLEEP_SECS="${SLEEP_SECS:-3}"

# prüfe, ob Service existiert
docker compose -f "$FILE" ps "$SVC" >/dev/null

echo "Smoke-Test DEV: warte bis $URL im Container $SVC erreichbar ist (${RETRIES} Versuche, alle ${SLEEP_SECS}s)…"
for i in $(seq 1 "$RETRIES"); do
  if docker compose -f "$FILE" exec -T "$SVC" sh -lc "curl -fsS '$URL' >/dev/null"; then
    echo "Smoke DEV OK: $URL erreichbar"
    exit 0
  fi
  echo "Warte auf Odoo DEV (${i}/${RETRIES})…"
  sleep "$SLEEP_SECS"
done

echo "Smoke-Test DEV fehlgeschlagen"
exit 1
