import asyncio
import json
import logging
import os
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from openai import AsyncOpenAI
from core.config import settings

logger = logging.getLogger("agi_agent")
router = APIRouter()

FILES_BASE = os.environ.get("FILES_BASE_PATH", "/data/files")
APP_ROOT = os.environ.get("AI_IDE_ROOT", "/app")

TOOLS = [
    {"type": "function", "function": {
        "name": "read_file",
        "description": "Lee el contenido de un archivo del servidor",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string", "description": "Ruta absoluta del archivo"}
        }, "required": ["path"]},
    }},
    {"type": "function", "function": {
        "name": "write_file",
        "description": "Crea o sobreescribe un archivo en el área de datos permitida",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"},
            "content": {"type": "string"},
        }, "required": ["path", "content"]},
    }},
    {"type": "function", "function": {
        "name": "list_files",
        "description": "Lista archivos y carpetas de un directorio",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}
        }, "required": ["path"]},
    }},
    {"type": "function", "function": {
        "name": "read_claude_rules",
        "description": "Lee las reglas y contexto de Antigravity AI",
        "parameters": {"type": "object", "properties": {}, "required": []},
    }},
]

SYSTEM_PROMPT = (
    "Eres un agente orquestador de Antigravity AI con acceso controlado al sistema de archivos del servidor. "
    "Puedes leer/escribir archivos dentro de los directorios permitidos y modificar código mediante herramientas limitadas. "
    "No puedes ejecutar comandos de shell.\n"
    "Reglas AG-CORE: no dejes catch vacíos, no uses credenciales en texto plano, "
    "sanitiza inputs en capa de entrada, no uses console.log/print en producción.\n"
    "Cuando el usuario pida crear o modificar algo, hazlo directamente con las herramientas disponibles. "
    "Explica brevemente qué hiciste después de cada acción."
)


def _safe_path(path: str) -> str:
    """Resolve and validate path stays within allowed roots."""
    resolved = os.path.realpath(path)
    allowed = [os.path.realpath(FILES_BASE), os.path.realpath(APP_ROOT)]
    if any(resolved.startswith(root) for root in allowed):
        return resolved
    raise PermissionError(f"Ruta fuera del área permitida: {path}")


def _exec_tool(name: str, args: dict) -> str:
    try:
        if name == "read_file":
            path = _safe_path(args["path"])
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
            return content[:10000] if len(content) > 10000 else content

        elif name == "write_file":
            path = _safe_path(args["path"])
            os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                f.write(args["content"])
            return f"Guardado: {path}"

        elif name == "list_files":
            path = _safe_path(args["path"])
            entries = os.listdir(path)
            dirs = [f"[DIR] {e}" for e in entries if os.path.isdir(os.path.join(path, e))]
            files = [f"[FILE] {e}" for e in entries if not os.path.isdir(os.path.join(path, e))]
            return "\n".join(dirs + files)

        elif name == "read_claude_rules":
            rules = []
            for p in [
                os.path.join(APP_ROOT, "CLAUDE.md"),
                os.path.join(APP_ROOT, "guia", "policies.md"),
            ]:
                if os.path.exists(p):
                    with open(p, "r", encoding="utf-8", errors="replace") as f:
                        rules.append(f"=== {p} ===\n{f.read()[:3000]}")
            return "\n\n".join(rules) or "No se encontraron archivos de reglas en el servidor"

    except PermissionError as e:
        logger.warning("AGI tool permission denied: %s", e)
        return f"Acceso denegado: {e}"
    except Exception as e:
        logger.error("AGI tool %s error: %s", name, e)
        return f"Error en {name}: {e}"
    return "Herramienta desconocida"


def _get_async_client(provider: str, key: str) -> tuple[AsyncOpenAI, str]:
    if provider == "cerebras":
        return AsyncOpenAI(api_key=key, base_url="https://api.cerebras.ai/v1"), "llama-3.3-70b"
    elif provider == "gemini":
        return AsyncOpenAI(
            api_key=key,
            base_url="https://generativelanguage.googleapis.com/v1beta/openai/",
        ), "gemini-2.0-flash"
    elif provider == "openrouter":
        app_url = os.environ.get("APP_BASE_URL", settings.app_base_url)
        return AsyncOpenAI(
            api_key=key,
            base_url="https://openrouter.ai/api/v1",
            default_headers={"HTTP-Referer": app_url, "X-Title": "Antigravity AI"},
        ), "meta-llama/llama-3.3-70b-instruct:free"
    else:  # groq default
        return AsyncOpenAI(
            api_key=key, base_url="https://api.groq.com/openai/v1"
        ), "llama-3.3-70b-versatile"


@router.websocket("/agi/stream")
async def agi_agent(ws: WebSocket):
    await ws.accept()
    try:
        while True:
            data = await ws.receive_json()
            prompt = data.get("prompt", "")
            provider = data.get("provider", "groq")
            model = data.get("model", "")
            client_keys: dict = data.get("api_keys", {})

            key_map = {
                "groq": settings.groq_api_key.strip(),
                "cerebras": settings.cerebras_api_key.strip(),
                "gemini": settings.gemini_api_key.strip(),
                "openrouter": settings.openrouter_api_key.strip(),
            }
            key = client_keys.get(provider, "").strip() or key_map.get(provider, "")
            if not key:
                await ws.send_text(f"[AGI: API key de {provider} no configurada]")
                await ws.send_json({"done": True, "code": 1})
                continue

            client, default_model = _get_async_client(provider, key)
            use_model = model or default_model

            messages = [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ]

            try:
                for _ in range(15):
                    response = await client.chat.completions.create(
                        model=use_model,
                        messages=messages,
                        tools=TOOLS,
                        tool_choice="auto",
                        stream=False,
                    )
                    msg = response.choices[0].message

                    if msg.tool_calls:
                        tool_calls_data = [
                            {
                                "id": tc.id,
                                "type": "function",
                                "function": {"name": tc.function.name, "arguments": tc.function.arguments},
                            }
                            for tc in msg.tool_calls
                        ]
                        messages.append({"role": "assistant", "content": msg.content or "", "tool_calls": tool_calls_data})

                        for tc in msg.tool_calls:
                            args = json.loads(tc.function.arguments)
                            preview = ", ".join(f"{k}={repr(v)[:25]}" for k, v in args.items() if k != "content")
                            await ws.send_text(f"\n**{tc.function.name}**({preview})\n")
                            result = await asyncio.to_thread(_exec_tool, tc.function.name, args)
                            await ws.send_text(f"```\n{result[:500]}\n```\n" if len(result) > 50 else f"`{result}`\n")
                            messages.append({"role": "tool", "tool_call_id": tc.id, "content": result})
                    else:
                        await ws.send_text(msg.content or "")
                        break

            except Exception as e:
                logger.error("AGI [%s] error: %s", provider, e)
                await ws.send_text(f"[Error AGI {provider}: {e}]")

            await ws.send_json({"done": True, "code": 0, "provider": provider, "model": use_model})

    except WebSocketDisconnect:
        pass
    except Exception as e:
        logger.error("AGI WS error: %s", e)
