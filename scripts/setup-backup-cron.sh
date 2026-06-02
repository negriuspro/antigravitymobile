#!/usr/bin/env bash
# setup-backup-cron.sh — Instala systemd timer para backup automático cada 6 horas
# P3-FIX: Implementa el requerimiento "Backup automático cada 6 horas"
# Uso: sudo bash scripts/setup-backup-cron.sh [--uninstall]
# Requiere: sudo, systemd (Ubuntu 25.x ✓)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE_NAME="antigravity-backup"
DEPLOY_USER="${SUDO_USER:-$(whoami)}"
DEPLOY_PATH="/opt/antigravitymobile"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[CRON]${NC} $*"; }
warn() { echo -e "${YELLOW}[CRON WARN]${NC} $*"; }

if [ "${1:-}" = "--uninstall" ]; then
  info "Desinstalando timer..."
  systemctl stop  "${SERVICE_NAME}.timer" 2>/dev/null || true
  systemctl disable "${SERVICE_NAME}.timer" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
  rm -f "/etc/systemd/system/${SERVICE_NAME}.timer"
  systemctl daemon-reload
  info "Timer eliminado."
  exit 0
fi

[ "$(id -u)" -eq 0 ] || { echo "ERROR: Ejecutar con sudo"; exit 1; }

info "Configurando backup automático cada 6 horas..."
info "Usuario: $DEPLOY_USER"
info "Ruta: $DEPLOY_PATH"

# ── Crear el .service ─────────────────────────────────────────────────────────
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=AntigravityMobile — Backup automático
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=${DEPLOY_USER}
WorkingDirectory=${DEPLOY_PATH}
ExecStart=/usr/bin/bash ${DEPLOY_PATH}/scripts/backup.sh --silent
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

# Evitar que un backup fallido bloquee el siguiente
SuccessExitStatus=0 1
EOF

# ── Crear el .timer ───────────────────────────────────────────────────────────
cat > "/etc/systemd/system/${SERVICE_NAME}.timer" <<EOF
[Unit]
Description=AntigravityMobile — Timer backup cada 6 horas
Requires=${SERVICE_NAME}.service

[Timer]
# Backup a las 00:00, 06:00, 12:00, 18:00 UTC
OnCalendar=*-*-* 00,06,12,18:00:00
# Pequeño delay aleatorio para no saturar disco al momento exacto
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
EOF

# ── Activar ───────────────────────────────────────────────────────────────────
systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.timer"

info ""
info "✓ Timer instalado y activo"
info ""
info "Próximas ejecuciones:"
systemctl list-timers "${SERVICE_NAME}.timer" --no-pager 2>/dev/null || true

info ""
info "Comandos útiles:"
info "  Ver logs:       journalctl -u ${SERVICE_NAME}.service -f"
info "  Estado timer:   systemctl status ${SERVICE_NAME}.timer"
info "  Ejecutar ahora: systemctl start ${SERVICE_NAME}.service"
info "  Desinstalar:    sudo bash scripts/setup-backup-cron.sh --uninstall"
