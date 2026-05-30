#!/usr/bin/env bash
# update.sh — Actualizar desde git y redeploy sin downtime
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

echo "=== Antigravity Mobile — Update ==="
date

# Detectar Docker Compose
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  echo "ERROR: Docker Compose no encontrado."; exit 1
fi

# 1. Pull
echo ""
echo "[1/4] Descargando últimos cambios..."
git fetch origin
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse @{u})

if [ "$LOCAL" = "$REMOTE" ]; then
  echo "Ya estás en la última versión ($LOCAL)."
  read -rp "¿Forzar rebuild de todas formas? [s/N] " force
  [[ "$force" =~ ^[sS]$ ]] || exit 0
fi

git pull --rebase

# 2. Build nuevas imágenes
echo ""
echo "[2/4] Construyendo imágenes actualizadas..."
$COMPOSE build --no-cache

# 3. Redeploy con rolling restart (zero-downtime)
echo ""
echo "[3/4] Aplicando actualización..."
$COMPOSE up -d

# 4. Limpieza de imágenes antiguas
echo ""
echo "[4/4] Limpiando imágenes obsoletas..."
docker image prune -f

# Estado final
echo ""
$COMPOSE ps
echo ""

HTTP_PORT=$(grep PUBLIC_HTTP_PORT .env 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || echo "3000")
HTTP_PORT="${HTTP_PORT:-3000}"

if curl -sf "http://localhost:${HTTP_PORT}/health" >/dev/null; then
  echo "OK — http://$(hostname -I | awk '{print $1}'):${HTTP_PORT}"
else
  echo "AVISO: /health no responde. Revisa: docker compose logs -f backend"
fi

echo ""
echo "=== Update completado — commit: $(git rev-parse --short HEAD) ==="
