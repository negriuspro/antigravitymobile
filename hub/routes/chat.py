import json
import logging
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from core.ws_manager import manager
from providers.anthropic import stream_claude
from providers.groq import stream_groq
from providers.cerebras import stream_cerebras
from providers.gemini import stream_gemini
from providers.codex import stream_codex
from providers.openrouter import stream_openrouter

logger = logging.getLogger("chat")
router = APIRouter()

PROVIDERS = {
    "claude": stream_claude,
    "groq": stream_groq,
    "cerebras": stream_cerebras,
    "gemini": stream_gemini,
    "codex": stream_codex,
    "openrouter": stream_openrouter,
}


@router.websocket("/ws/chat")
async def chat_ws(ws: WebSocket):
    await manager.connect(ws)
    try:
        while True:
            raw = await ws.receive_text()
            data = json.loads(raw)
            provider = data.get("provider", "claude")
            messages = data.get("messages", [])
            model = data.get("model")
            thinking_budget = data.get("thinking_budget")
            image = data.get("image")
            image_mime = data.get("image_mime", "image/jpeg")
            # Per-request API keys from the mobile client (override hub .env)
            api_keys: dict = data.get("api_keys", {})

            stream_fn = PROVIDERS.get(provider, stream_claude)
            await manager.send(ws, json.dumps({"type": "start", "provider": provider}))
            try:
                kwargs = {}
                if model:
                    kwargs["model"] = model
                # Pass caller's API key if provided
                if provider in api_keys and api_keys[provider]:
                    kwargs["api_key"] = api_keys[provider]
                # Gemini-specific extras
                if provider == "gemini":
                    if thinking_budget:
                        kwargs["thinking_budget"] = thinking_budget
                    if image:
                        kwargs["image"] = image
                        kwargs["image_mime"] = image_mime
                async for chunk in stream_fn(messages, **kwargs):
                    await manager.send(ws, json.dumps({"type": "chunk", "text": chunk}))
            except Exception as e:
                logger.error(f"Provider {provider} error: {e}")
                await manager.send(ws, json.dumps({"type": "chunk", "text": f"[Error: {e}]"}))
            await manager.send(ws, json.dumps({"type": "end"}))

    except WebSocketDisconnect:
        manager.disconnect(ws)
    except Exception as e:
        logger.error(f"chat_ws error: {e}")
        manager.disconnect(ws)
