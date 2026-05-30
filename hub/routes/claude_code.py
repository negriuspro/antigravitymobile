import logging
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

logger = logging.getLogger("claude_code")
router = APIRouter()


async def _disabled_shell_agent(ws: WebSocket, agent_name: str):
    await ws.accept()
    logger.info("%s websocket connected; shell execution is disabled", agent_name)
    try:
        while True:
            await ws.receive_json()
            await ws.send_text(
                f"{agent_name} CLI execution is disabled in Docker mode. "
                "Use provider API keys or the allowed Docker container endpoints."
            )
            await ws.send_json({"done": True, "code": 403})
    except WebSocketDisconnect:
        logger.info("%s websocket disconnected", agent_name)
    except Exception as exc:
        logger.exception("%s websocket error: %s", agent_name, exc)


@router.websocket("/claude/stream")
async def stream_claude_code(ws: WebSocket):
    await _disabled_shell_agent(ws, "Claude Code")


@router.websocket("/codex/stream")
async def stream_codex_code(ws: WebSocket):
    await _disabled_shell_agent(ws, "Codex")
