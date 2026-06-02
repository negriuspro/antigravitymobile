#!/usr/bin/env bash
# update.sh — Actualizar desde git con rollback automático si falla healthcheck
# Uso: bash scripts/update.sh [--force] [--no-cache]
# P9-FIX: sin prompts interactivos por defecto; usar --force para forzar rebuild
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

FORCE_REBUILD=0
BUILD_NOCACHE=""
for arg in "$@"; do
  case "$arg" in
    --force)    FORCE_REBUILD=1 ;;
    --no-cache) BUILD_NOCACHE="--no-cache" ;;
  esac
done

echo "=== AntigravityMobile — Update ==="
date

PREV_COMMIT=$(git rev-parse HEAD)

# ── 1. Backup preventivo ─────────────────────────────────────────────────────
info "[1/5] Backup previo al update..."
bash "$REPO_DIR/scripts/backup.sh" --silent || warn "Backup falló, continuando"

# ── 2. Git pull ──────────────────────────────────────────────────────────────
info "[2/5] Descargando cambios..."
git fetch origin
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "@{u}" 2>/dev/null || echo "")

if [ -n "$REMOTE" ] && [ "$LOCAL" = "$REMOTE" ]; then
  warn "Ya en la última versión ($(echo "$LOCAL" | cut -c1-7))."
  if [ "$FORCE_REBUILD" -eq 0 ]; then
    # P9-FIX: no colgar si no hay TTY — si no hay terminal, salir limpiamente
    if [ -t 0 ]; then
      read -rp "¿Forzar rebuild de todas formas? [s/N] " force
      [[ "$force" =~ ^[sS]$ ]] || exit 0
    else
      info "Sin cambios y sin --force. Saliendo."
      exit 0
    fi
  fi
fi

git pull --rebase

NEW_COMMIT=$(git rev-parse --short HEAD)
info "Commit nuevo: $NEW_COMMIT (anterior: $(echo "$PREV_COMMIT" | cut -c1-7))"

# ── 3. Build imágenes ─────────────────────────────────────────────────────────
info "[3/5] Construyendo imágenes..."
# P6-FIX: Sin --no-cache por defecto — Docker usa layer cache cuando el código
# no cambió, ahorrando 1-2 GB de RAM durante el build de Flutter.
# Pasar --no-cache explícitamente solo cuando sea necesario.
# shellcheck disable=SC2086
docker compose build $BUILD_NOCACHE

# ── 4. Rolling restart ────────────────────────────────────────────────────────
info "[4/5] Aplicando update..."
# P4-FIX: up -d en lugar de down+up — no destruye containers, rolling restart
docker compose up -d --remove-orphans

# ── 5. Healthcheck con rollback automático ────────────────────────────────────
info "[5/5] Verificando healthcheck..."
sleep 20

HTTP_PORT=$(grep '^PUBLIC_HTTP_PORT=' .env | cut -d= -f2 | tr -d '[:space:]' || echo "80")
HTTP_PORT="${HTTP_PORT:-80}"

MAX_RETRIES=6
RETRY=0
while ! curl -sf "http://localhost:${HTTP_PORT}/health" >/dev/null 2>&1; do
  RETRY=$((RETRY + 1))
  if [[ $RETRY -ge $MAX_RETRIES ]]; then
    error "Healthcheck falló. Iniciando rollback automático a $PREV_COMMIT..."
    ROLLBACK_TO="$PREV_COMMIT" bash "$REPO_DIR/scripts/rollback.sh"
    exit 1
  fi
  warn "Healthcheck pending... intento $RETRY/$MAX_RETRIES"
  sleep 5
done

# Limpieza de imágenes antiguas — solo si hay más de 3 versiones guardadas
docker image prune -f >/dev/null 2>&1 || true

docker compose ps
echo ""
info "Update completado — commit: $NEW_COMMIT"
info "URL: http://$(hostname -I | awk '{print $1}'):${HTTP_PORT}"
