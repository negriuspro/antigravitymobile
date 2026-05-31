# Antigravity Mobile

Self-hosted Flutter Web panel plus FastAPI hub for Antigravity AI.

## Docker WSL Start

Run from Ubuntu WSL, where Docker Engine is installed:

```bash
cd /mnt/c/Users/je416/Desktop/AntigravityMobile
docker compose up -d --build
```

Open:

```text
http://localhost:3000
```

From a tablet on the same LAN:

```text
http://YOUR_PC_LAN_IP:3000
```

## Architecture

```text
Tablet / Browser
  -> Nginx gateway :3000
      -> Flutter Web static frontend
      -> FastAPI backend :8000
          -> Docker SDK over /var/run/docker.sock
          -> Redis
```

The Docker socket is mounted only into the backend. It is never exposed over TCP, and the frontend never talks to Docker directly.

## Operations

```bash
docker compose ps
docker compose logs -f
docker compose restart
docker compose down
docker compose build --no-cache
docker compose up -d
```

Development override:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
```

Full WSL and LAN notes are in `docs/DOCKER_WSL.md`.

## Services

- `nginx`: public gateway on `0.0.0.0:3000`, WebSocket proxy, gzip, SPA routing through frontend
- `frontend`: Flutter Web production build served by Nginx
- `backend`: FastAPI bound to `0.0.0.0:8000` inside Docker
- `redis`: internal state/cache service
- `future-services`: disabled placeholder profile
# test
