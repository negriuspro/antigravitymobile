# dev-start.ps1 — antigravitymobile en modo local (sin Docker)
# Arranca: Redis tunnel → Backend (uvicorn) → Frontend (Flutter)
# Uso: .\dev-start.ps1

$ROOT     = $PSScriptRoot
$SERVER   = "angel@192.168.100.6"
$BACKEND  = "$ROOT\hub"
$FRONTEND = "$ROOT\mobile"

Write-Host "`n=== AntigravityMobile DEV ===" -ForegroundColor Cyan

# ── 1. SSH tunnel → Redis del servidor en localhost:6380 ───────────────────
# Usamos 6380 para no chocar con angel-ctrl que usa 6379
Write-Host "[1/3] Iniciando SSH tunnel Redis (localhost:6380 → servidor)..." -ForegroundColor Yellow
$tunnel = Start-Process "ssh" -ArgumentList "-N -L 6380:localhost:6379 $SERVER" -PassThru -WindowStyle Hidden
Write-Host "      Tunnel PID: $($tunnel.Id)" -ForegroundColor DarkGray
Start-Sleep -Seconds 2

# ── 2. Backend FastAPI ─────────────────────────────────────────────────────
Write-Host "[2/3] Instalando dependencias backend..." -ForegroundColor Yellow
Push-Location $BACKEND
pip install -r requirements.txt -q

# Crear .env.dev si no existe
if (-not (Test-Path ".env.dev")) {
    @"
HUB_HOST=0.0.0.0
HUB_PORT=8000
REDIS_URL=redis://localhost:6380/0
DOCKER_HOST=npipe:////./pipe/docker_engine
LOG_LEVEL=debug
# Agrega tus API keys reales aqui:
ANTHROPIC_API_KEY=
GROQ_API_KEY=
GEMINI_API_KEY=
CEREBRAS_API_KEY=
OPENROUTER_API_KEY=
SAMBANOVA_API_KEY=
"@ | Out-File ".env.dev" -Encoding utf8
    Write-Host "      .env.dev creado — agrega tus API keys" -ForegroundColor DarkYellow
}

Write-Host "[2/3] Arrancando backend en http://localhost:8000..." -ForegroundColor Yellow
Start-Process "powershell" -ArgumentList "-NoExit", "-Command",
    "cd '$BACKEND'; Get-Content '.env.dev' | ForEach-Object { if(`$_ -match '^([^#=]+)=(.*)$') { [System.Environment]::SetEnvironmentVariable(`$matches[1].Trim(), `$matches[2].Trim()) } }; python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload"
Pop-Location

Start-Sleep -Seconds 3

# ── 3. Frontend Flutter ────────────────────────────────────────────────────
Write-Host "[3/3] Arrancando Flutter web en http://localhost:5001..." -ForegroundColor Yellow
Push-Location $FRONTEND
Start-Process "powershell" -ArgumentList "-NoExit", "-Command",
    "cd '$FRONTEND'; flutter run -d chrome --web-port 5001 --dart-define=API_URL=http://localhost:8000"
Pop-Location

Write-Host "`n✓ AntigravityMobile corriendo localmente:" -ForegroundColor Green
Write-Host "  Backend:  http://localhost:8000/health" -ForegroundColor White
Write-Host "  Frontend: http://localhost:5001" -ForegroundColor White
Write-Host "  Redis:    tunnel → 192.168.100.6:6379 (local port 6380)" -ForegroundColor White
Write-Host "  IMPORTANTE: Edita hub\.env.dev con tus API keys reales`n" -ForegroundColor DarkYellow
