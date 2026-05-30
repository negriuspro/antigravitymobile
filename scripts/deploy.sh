#!/usr/bin/env bash
# deploy.sh — Primera instalación en Ubuntu Server
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

echo "=== Antigravity Mobile — Deploy ==="
echo "Directorio: $REPO_DIR"

# 1. Verificar dependencias
for cmd in docker git curl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: '$cmd' no está instalado."; exit 1; }
done

# Docker Compose V2 (plugin) o V1 (standalone)
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  echo "ERROR: Docker Compose no encontrado."; exit 1
fi

# 2. Crear .env si no existe
if [ ! -f .env ]; then
  cp .env.example .env
  echo ""
  echo "AVISO: Se creó .env desde .env.example."
  echo "Edita .env con tus API keys antes de continuar:"
  echo "  nano .env"
  echo ""
  read -rp "¿Ya editaste .env? [s/N] " confirm
  [[ "$confirm" =~ ^[sS]$ ]] || { echo "Edita .env y vuelve a ejecutar deploy.sh"; exit 0; }
fi

# 3. Crear directorio de archivos persistente
sudo mkdir -p /opt/antigravity/files
sudo chown -R 1000:1000 /opt/antigravity/files
echo "Directorio /opt/antigravity/files listo."

# 4. Build y levantar
echo ""
echo "Construyendo imágenes y levantando servicios..."
$COMPOSE up -d --build

# 5. Esperar healthchecks
echo "Esperando que los servicios estén healthy..."
sleep 10

# 6. Verificar
$COMPOSE ps
echo ""
echo "Verificando endpoint /health ..."
HTTP_PORT=$(grep PUBLIC_HTTP_PORT .env | cut -d= -f2 | tr -d '[:space:]' || echo "3000")
HTTP_PORT="${HTTP_PORT:-3000}"

if curl -sf "http://localhost:${HTTP_PORT}/health" >/dev/null; then
  echo "OK — La app responde en http://$(hostname -I | awk '{print $1}'):${HTTP_PORT}"
else
  echo "AVISO: El endpoint /health no responde aún. Espera unos segundos más."
  echo "Revisa logs con: docker compose logs -f backend"
fi

echo ""
echo "=== Deploy completado ==="
echo "URL: http://$(hostname -I | awk '{print $1}'):${HTTP_PORT}"
echo "Logs: docker compose logs -f"
echo "Stop: docker compose down"
