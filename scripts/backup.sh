#!/usr/bin/env bash
# backup.sh — Backup de Redis (dump.rdb) y volumen de archivos
# Uso: bash scripts/backup.sh [--silent]
# Cron: instalado por setup-backup-cron.sh (cada 6 horas)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

SILENT="${1:-}"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { [[ "$SILENT" != "--silent" ]] && echo -e "${GREEN}[BACKUP]${NC} $*" || true; }
warn()  { echo -e "${YELLOW}[BACKUP WARN]${NC} $*" >&2; }
error() { echo -e "${RED}[BACKUP ERROR]${NC} $*" >&2; exit 1; }

BACKUP_DIR="/opt/antigravitymobile/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP"
MAX_BACKUPS=28  # 7 días × 4 backups/día = 28 backups máximo

info "Iniciando backup — $TIMESTAMP"
mkdir -p "$BACKUP_PATH"

# ── 1. Redis BGSAVE con verificación de completado ────────────────────────────
info "Guardando snapshot Redis..."
REDIS_PW=$(grep '^REDIS_PASSWORD=' .env 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || echo "")

if docker compose ps redis 2>/dev/null | grep -qE "(Up|running)"; then
  # Disparar BGSAVE
  if [ -n "$REDIS_PW" ]; then
    docker compose exec -T redis redis-cli -a "$REDIS_PW" BGSAVE >/dev/null 2>&1 || warn "BGSAVE falló"
  else
    docker compose exec -T redis redis-cli BGSAVE >/dev/null 2>&1 || warn "BGSAVE falló"
  fi

  # P12-FIX: esperar que BGSAVE realmente complete en lugar de sleep fijo
  # LASTSAVE retorna unix timestamp del último save exitoso
  SAVE_STARTED=$(date +%s)
  MAX_WAIT=30
  WAITED=0
  while true; do
    LAST_SAVE=""
    if [ -n "$REDIS_PW" ]; then
      LAST_SAVE=$(docker compose exec -T redis redis-cli -a "$REDIS_PW" LASTSAVE 2>/dev/null | tr -d '\r' || echo "0")
    else
      LAST_SAVE=$(docker compose exec -T redis redis-cli LASTSAVE 2>/dev/null | tr -d '\r' || echo "0")
    fi

    if [ -n "$LAST_SAVE" ] && [ "$LAST_SAVE" -ge "$SAVE_STARTED" ] 2>/dev/null; then
      info "Redis BGSAVE completado (LASTSAVE: $LAST_SAVE)"
      break
    fi

    WAITED=$((WAITED + 2))
    if [ $WAITED -ge $MAX_WAIT ]; then
      warn "Timeout esperando BGSAVE, copiando dump de todas formas"
      break
    fi
    sleep 2
  done

  # Copiar dump.rdb desde el volumen usando un container efímero
  docker run --rm \
    --network none \
    -v antigravitymobile_redis-data:/data:ro \
    -v "${BACKUP_PATH}:/backup" \
    alpine:3.20 \
    sh -c "cp /data/dump.rdb /backup/redis_dump.rdb 2>/dev/null && \
           echo 'dump.rdb copiado' || echo 'dump.rdb no encontrado'" \
    >/dev/null 2>&1 || warn "No se pudo copiar redis dump"

  info "Redis backup: $BACKUP_PATH/redis_dump.rdb"
else
  warn "Redis no está corriendo — saltando backup de Redis"
fi

# ── 2. Backup del volumen de archivos ─────────────────────────────────────────
info "Comprimiendo volumen de archivos..."
docker run --rm \
  --network none \
  -v antigravitymobile_files-data:/data:ro \
  -v "${BACKUP_PATH}:/backup" \
  alpine:3.20 \
  tar -czf /backup/files_data.tar.gz -C /data . 2>/dev/null || warn "No se pudo comprimir volumen de archivos"

# Verificar tamaño mínimo (al menos 20 bytes)
if [ -f "$BACKUP_PATH/files_data.tar.gz" ]; then
  FILE_SIZE=$(stat -c%s "$BACKUP_PATH/files_data.tar.gz" 2>/dev/null || echo 0)
  if [ "$FILE_SIZE" -lt 20 ]; then
    warn "files_data.tar.gz demasiado pequeño ($FILE_SIZE bytes) — posiblemente vacío"
  else
    info "Files backup: $BACKUP_PATH/files_data.tar.gz ($(du -sh "$BACKUP_PATH/files_data.tar.gz" | cut -f1))"
  fi
fi

# ── 3. Metadata ────────────────────────────────────────────────────────────────
git rev-parse HEAD > "$BACKUP_PATH/git_commit.txt" 2>/dev/null || echo "unknown" > "$BACKUP_PATH/git_commit.txt"
echo "$TIMESTAMP" > "$BACKUP_PATH/timestamp.txt"
docker compose ps --format json > "$BACKUP_PATH/services_state.json" 2>/dev/null || true
info "Commit guardado: $(cut -c1-7 "$BACKUP_PATH/git_commit.txt")"

# ── 4. Rotación de backups viejos ──────────────────────────────────────────────
BACKUP_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d -name '[0-9]*' 2>/dev/null | wc -l || echo 0)
if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
  EXCESS=$((BACKUP_COUNT - MAX_BACKUPS))
  find "$BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d -name '[0-9]*' | sort | head -n "$EXCESS" | xargs rm -rf
  info "Rotación: eliminados $EXCESS backups antiguos (retenidos: $MAX_BACKUPS)"
fi

info "Backup completado → $BACKUP_PATH"
info "Espacio total backups: $(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo 'desconocido')"
