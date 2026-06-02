#!/usr/bin/env bash
# rollback.sh — Revertir al commit anterior y redeploy sin downtime
# Uso manual:  bash scripts/rollback.sh
# Uso interno: ROLLBACK_TO=<sha> bash scripts/rollback.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo "=== AntigravityMobile — Rollback ==="
date

CURRENT_COMMIT=$(git rev-parse HEAD)

# Determinar commit destino
if [ -n "${ROLLBACK_TO:-}" ]; then
  TARGET_COMMIT="${ROLLBACK_TO}"
  info "Rollback automático a: $(echo "$TARGET_COMMIT" | cut -c1-7)"
else
  echo ""
  info "Historial reciente:"
  git log --oneline -10
  echo ""
  read -rp "SHA del commit al que revertir (Enter = HEAD~1): " TARGET_COMMIT
  TARGET_COMMIT="${TARGET_COMMIT:-HEAD~1}"
fi

TARGET_SHA=$(git rev-parse "$TARGET_COMMIT" 2>/dev/null) || error "Commit '$TARGET_COMMIT' no encontrado."
TARGET_SHORT=$(git rev-parse --short "$TARGET_SHA")

warn "Rollback: $(echo "$CURRENT_COMMIT" | cut -c1-7) → $TARGET_SHORT"

# P9-FIX: si ROLLBACK_TO está definido (llamada automática), no preguntar
if [ -z "${ROLLBACK_TO:-}" ]; then
  read -rp "¿Confirmar rollback? [s/N] " confirm
  [[ "${confirm}" =~ ^[sS]$ ]] || { info "Cancelado."; exit 0; }
fi

# ── 1. Backup del estado actual ──────────────────────────────────────────────
info "[1/4] Backup del estado actual..."
bash "$REPO_DIR/scripts/backup.sh" --silent || warn "Backup falló, continuando"

# ── 2. Revertir código ────────────────────────────────────────────────────────
# P8-FIX: Usar git stash + reset en lugar de git checkout SHA -- .
# Esto mantiene el estado del repo limpio y el HEAD apuntando correctamente.
info "[2/4] Revirtiendo código a $TARGET_SHORT..."
git stash push -m "rollback-safety-stash-$(date +%s)" 2>/dev/null || true
git reset --hard "$TARGET_SHA"

# ── 3. Rebuild con código anterior ────────────────────────────────────────────
info "[3/4] Reconstruyendo imágenes (versión $TARGET_SHORT)..."
# P4-FIX: NO usar docker compose down. Usar build + up para rolling restart
# sin borrar containers (Redis mantiene datos en memoria + AOF persistente)
docker compose build
docker compose up -d --remove-orphans

# ── 4. Verificar rollback ─────────────────────────────────────────────────────
info "[4/4] Verificando healthcheck post-rollback..."
sleep 20

HTTP_PORT=$(grep '^PUBLIC_HTTP_PORT=' .env | cut -d= -f2 | tr -d '[:space:]' || echo "80")
HTTP_PORT="${HTTP_PORT:-80}"

MAX_RETRIES=6; RETRY=0
while ! curl -sf "http://localhost:${HTTP_PORT}/health" >/dev/null 2>&1; do
  RETRY=$((RETRY + 1))
  [[ $RETRY -ge $MAX_RETRIES ]] && error "Healthcheck falló incluso tras rollback. Intervención manual requerida."
  warn "Esperando... $RETRY/$MAX_RETRIES"
  sleep 5
done

docker compose ps
echo ""
info "Rollback completado → commit: $TARGET_SHORT"
info "HEAD apunta a: $(git log --oneline -1)"
warn "Si necesitas volver al master: git pull origin master && bash scripts/update.sh"
