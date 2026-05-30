import asyncio
from typing import Any

import docker
from docker.errors import APIError, DockerException, NotFound
from fastapi import APIRouter, HTTPException, Query

from core.config import settings

router = APIRouter(prefix="/servers", tags=["servers"])


def _client() -> docker.DockerClient:
    try:
        return docker.from_env()
    except DockerException as exc:
        raise HTTPException(status_code=503, detail="Docker engine unavailable") from exc


def _label_filter() -> dict[str, str]:
    key, _, value = settings.docker_allowed_label.partition("=")
    if not key or not value:
        raise HTTPException(status_code=500, detail="Invalid Docker label policy")
    return {key: value}


def _serialize(container: Any) -> dict[str, Any]:
    attrs = container.attrs
    state = attrs.get("State", {})
    config = attrs.get("Config", {})
    network = attrs.get("NetworkSettings", {})
    return {
        "id": container.short_id,
        "name": container.name,
        "image": attrs.get("Image", ""),
        "status": container.status,
        "state": state.get("Status", ""),
        "running": bool(state.get("Running", False)),
        "labels": config.get("Labels") or {},
        "ports": network.get("Ports") or {},
        "created": attrs.get("Created", ""),
    }


def _get_allowed_container(container_id: str):
    client = _client()
    try:
        container = client.containers.get(container_id)
        labels = container.attrs.get("Config", {}).get("Labels") or {}
    except NotFound as exc:
        raise HTTPException(status_code=404, detail="Container not found") from exc
    except APIError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    for key, value in _label_filter().items():
        if labels.get(key) != value:
            raise HTTPException(status_code=403, detail="Container is outside the allowed management scope")
    return container


async def _run_blocking(func, *args, **kwargs):
    return await asyncio.to_thread(func, *args, **kwargs)


@router.get("")
async def list_containers(all: bool = Query(default=True)):
    def op():
        client = _client()
        containers = client.containers.list(all=all, filters={"label": settings.docker_allowed_label})
        return [_serialize(c) for c in containers]

    return {"containers": await _run_blocking(op)}


@router.get("/{container_id}")
async def inspect_container(container_id: str):
    container = await _run_blocking(_get_allowed_container, container_id)
    return {"container": _serialize(container), "raw": container.attrs}


@router.post("/{container_id}/start")
async def start_container(container_id: str):
    container = await _run_blocking(_get_allowed_container, container_id)
    await _run_blocking(container.start)
    return {"status": "started", "container": container.name}


@router.post("/{container_id}/stop")
async def stop_container(container_id: str):
    container = await _run_blocking(_get_allowed_container, container_id)
    await _run_blocking(container.stop, timeout=10)
    return {"status": "stopped", "container": container.name}


@router.post("/{container_id}/restart")
async def restart_container(container_id: str):
    container = await _run_blocking(_get_allowed_container, container_id)
    await _run_blocking(container.restart, timeout=10)
    return {"status": "restarted", "container": container.name}


@router.get("/{container_id}/logs")
async def container_logs(container_id: str, tail: int = Query(default=200, ge=1, le=1000)):
    container = await _run_blocking(_get_allowed_container, container_id)
    logs = await _run_blocking(container.logs, tail=tail, timestamps=True)
    return {"container": container.name, "logs": logs.decode("utf-8", errors="replace")}


@router.get("/{container_id}/metrics")
async def container_metrics(container_id: str):
    container = await _run_blocking(_get_allowed_container, container_id)
    stats = await _run_blocking(container.stats, stream=False)
    return {"container": container.name, "metrics": stats}
