# Docker WSL Deployment

This project is designed to run with Docker Engine inside WSL Ubuntu.

## Start

```bash
cd /mnt/c/Users/je416/Desktop/AntigravityMobile
cp .env.example .env
docker compose up -d --build
```

## Access

Local WSL/Windows browser:

```text
http://localhost:3000
```

LAN tablet/device:

```bash
ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.'
```

Open:

```text
http://YOUR_LAN_IP:3000
```

The backend is not published directly in production. Tablets call the Flutter Web UI, which calls Nginx, which proxies REST and WebSocket traffic to FastAPI.

## Commands

Build and start:

```bash
docker compose up -d --build
```

Stop:

```bash
docker compose down
```

Restart:

```bash
docker compose restart
```

Logs:

```bash
docker compose logs -f
docker compose logs -f backend
docker compose logs -f nginx
```

Update/rebuild after changes:

```bash
docker compose build --no-cache
docker compose up -d
```

Development mode:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
```

## WSL LAN Notes

Docker must run inside Ubuntu WSL. Run all Docker commands from Ubuntu, not PowerShell.

Bind ports are configured on `0.0.0.0`. If a tablet cannot connect:

1. Confirm the service is listening: `docker compose ps`
2. Confirm Windows Firewall allows inbound TCP `3000`
3. Use the Windows host LAN IP when WSL NAT does not expose the WSL IP directly
4. Optional Windows port proxy from an elevated PowerShell:

```powershell
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=3000 connectaddress=<WSL_IP> connectport=3000
netsh advfirewall firewall add rule name="AntigravityMobile 3000" dir=in action=allow protocol=TCP localport=3000
```

## Security

Only the backend mounts `/var/run/docker.sock`. The Docker API is not exposed over TCP. The frontend never talks to Docker directly.

Backend Docker endpoints only support:

- list
- inspect
- start
- stop
- restart
- logs
- metrics

For mutating operations, containers must carry the label configured by `DOCKER_ALLOWED_LABEL`, defaulting to `com.antigravity.manage=true`.
