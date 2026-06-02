#!/usr/bin/env bash
# deploy.sh — Primera instalación en servidor Ubuntu
# Uso: bash scripts/deploy.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo "=== AntigravityMobile — Deploy inicial ==="
info "Directorio: $REPO_DIR"
date

# ── 1. Verificar dependencias ────────────────────────────────────────────────
for cmd in docker git curl; do
  command -v "$cmd" >/dev/null 2>&1 || error "'$cmd' no está instalado."
done

docker compose version >/dev/null 2>&1 || error "Docker Compose V2 no encontrado. Instala: https://docs.docker.com/compose/install/"

# ── 2. Crear .env si no existe ───────────────────────────────────────────────
if [ ! -f .env ]; then
  cp .env.example .env
  warn ".env creado desde .env.example"
  warn "Edita .env con tus valores reales y vuelve a ejecutar:"
  warn "  nano .env && bash scripts/deploy.sh"
  exit 0
fi

# Verificar que REDIS_PASSWORD no sea el valor de ejemplo
REDIS_PW=$(grep '^REDIS_PASSWORD=' .env | cut -d= -f2 || echo "")
if [[ "$REDIS_PW" == *"cambia_esto"* ]] || [[ -z "$REDIS_PW" ]]; then
  error "REDIS_PASSWORD en .env no está configurado. Genera uno con: openssl rand -hex 20"
fi

SECRET=$(grep '^SECRET_KEY=' .env | cut -d= -f2 || echo "")
if [[ "$SECRET" == *"cambia_esto"* ]] || [[ -z "$SECRET" ]]; then
  error "SECRET_KEY en .env no está configurado. Genera uno con: openssl rand -hex 32"
fi

# ── 3. Permisos del volumen de archivos ──────────────────────────────────────
info "Preparando directorios persistentes..."
sudo mkdir -p /opt/antigravitymobile/backups
sudo chown -R 1000:1000 /opt/antigravitymobile 2>/dev/null || true

# ── 4. Build y arranque ──────────────────────────────────────────────────────
info "Construyendo imágenes..."
docker compose build --no-cache

info "Levantando servicios..."
docker compose up -d --remove-orphans

# ── 5. Esperar y verificar healthchecks ─────────────────────────────────────
info "Esperando healthchecks (30s)..."
sleep 30

MAX_RETRIES=10
RETRY=0
HTTP_PORT=$(grep '^PUBLIC_HTTP_PORT=' .env | cut -d= -f2 | tr -d '[:space:]' || echo "80")
HTTP_PORT="${HTTP_PORT:-80}"

while ! curl -sf "http://localhost:${HTTP_PORT}/health" >/dev/null 2>&1; do
  RETRY=$((RETRY + 1))
  [[ $RETRY -ge $MAX_RETRIES ]] && error "Healthcheck falló tras ${MAX_RETRIES} intentos. Revisa: docker compose logs backend"
  warn "Esperando... intento $RETRY/$MAX_RETRIES"
  sleep 5
done

# ── 6. Estado final ──────────────────────────────────────────────────────────
docker compose ps
echo ""
info "Deploy completado — commit: $(git rev-parse --short HEAD)"
info "URL: http://$(hostname -I | awk '{print $1}'):${HTTP_PORT}"
info "Logs: docker compose logs -f"
