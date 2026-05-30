import asyncio
import json
import logging
import os
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from openai import OpenAI
from core.config import settings

logger = logging.getLogger("agi_agent")
router = APIRouter()

DEFAULT_CWD = os.environ.get("FILES_BASE_PATH", "/data/files")
AI_IDE_ROOT = os.environ.get("AI_IDE_ROOT", "/app")

TOOLS = [
    {"type": "function", "function": {"name": "read_file", "description": "Lee el contenido de un archivo del sistema", "parameters": {"type": "object", "properties": {"path": {"type": "string", "description": "Ruta absoluta del archivo"}}, "required": ["path"]}}},
    {"type": "function", "function": {"name": "write_file", "description": "Crea o sobreescribe un archivo", "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}}, "required": ["path", "content"]}}},
    {"type": "function", "function": {"name": "list_files", "description": "Lista archivos y carpetas de un directorio", "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
    {"type": "function", "function": {"name": "read_claude_rules", "description": "Lee las reglas y contexto de Antigravity AI (CLAUDE.md y STATE.md)", "parameters": {"type": "object", "properties": {}, "required": []}}},
]

SYSTEM_PROMPT = """Eres un agente orquestador de Antigravity AI con acceso controlado al sistema de archivos del servidor.
Puedes leer/escribir archivos dentro de los directorios permitidos y modificar código mediante herramientas limitadas.
No puedes ejecutar comandos de shell.
Sigues las reglas de Antigravity AI (AG-CORE):
- No dejes catch vacíos, siempre loguea errores
- No uses credenciales en texto plano
- Sanitiza inputs en capa de entrada
- No uses console.log/print en producción
Cuando el usuario pida crear o modificar algo, hazlo directamente con las herramientas disponibles.
Explica brevemente qué hiciste después de cada acción."""


def _exec_tool(name: str, args: dict) -> str:
    try:
        if name == "read_file":
            path = args["path"]
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
            return content[:10000] if len(content) > 10000 else content

        elif name == "write_file":
            path = args["path"]
            os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                f.write(args["content"])
            return f"✓ Guardado: {path}"

        elif name == "list_files":
            entries = os.listdir(args["path"])
            dirs = [f"📁 {e}" for e in entries if os.path.isdir(os.path.join(args["path"], e))]
            files = [f"📄 {e}" for e in entries if not os.path.isdir(os.path.join(args["path"], e))]
            return "\n".join(dirs + files)

        elif name == "read_claude_rules":
            rules = []
            for p in [
                os.path.join(DEFAULT_CWD, "CLAUDE.md"),
                os.path.join(AI_IDE_ROOT, "core", "policies.md"),
                os.path.join(DEFAULT_CWD, ".ai", "STATE.md"),
            ]:
                if os.path.exists(p):
                    with open(p, "r", encoding="utf-8", errors="replace") as f:
                        rules.append(f"=== {p} ===\n{f.read()[:3000]}")
            return "\n\n".join(rules) or "No se encontraron archivos de reglas"

    except Exception as e:
        return f"Error en {name}: {e}"
    return "Herramienta desconocida"


def _get_client(provider: str, key: str) -> tuple[OpenAI, str]:
    """Returns (client, base_model) for the given provider using the supplied key."""
    if provider == "cerebras":
        return OpenAI(api_key=key, base_url="https://api.cerebras.ai/v1"), "llama-3.3-70b"
    elif provider == "gemini":
        return OpenAI(api_key=key, base_url="https://generativelanguage.googleapis.com/v1beta/openai/"), "gemini-2.0-flash"
    elif provider == "openrouter":
        app_url = os.environ.get("APP_BASE_URL", "http://localhost:3000")
        client = OpenAI(
            api_key=key,
            base_url="https://openrouter.ai/api/v1",
            default_headers={"HTTP-Referer": app_url, "X-Title": "Antigravity AI"},
        )
        return client, "meta-llama/llama-3.3-70b-instruct:free"
    else:  # groq default
        return OpenAI(api_key=key, base_url="https://api.groq.com/openai/v1"), "llama-3.3-70b-versatile"


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
            # Client key overrides hub .env key
            key = client_keys.get(provider, "").strip() or key_map.get(provider, "")
            if not key:
                await ws.send_text(f"[AGI: API key de {provider} no configurada en hub/.env]")
                await ws.send_json({"done": True, "code": 1})
                continue

            client, default_model = _get_client(provider, key)
            use_model = model or default_model

            messages = [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ]

            try:
                for _ in range(15):
                    response = client.chat.completions.create(
                        model=use_model,
                        messages=messages,
                        tools=TOOLS,
                        tool_choice="auto",
                        stream=False,
                    )
                    msg = response.choices[0].message

                    if msg.tool_calls:
                        tool_calls_data = [{"id": tc.id, "type": "function", "function": {"name": tc.function.name, "arguments": tc.function.arguments}} for tc in msg.tool_calls]
                        messages.append({"role": "assistant", "content": msg.content or "", "tool_calls": tool_calls_data})

                        for tc in msg.tool_calls:
                            args = json.loads(tc.function.arguments)
                            preview = ", ".join(f"{k}={repr(v)[:25]}" for k, v in args.items() if k != "content")
                            await ws.send_text(f"\n🔧 **{tc.function.name}**({preview})\n")
                            result = await asyncio.to_thread(_exec_tool, tc.function.name, args)
                            await ws.send_text(f"```\n{result[:500]}\n```\n" if len(result) > 50 else f"`{result}`\n")
                            messages.append({"role": "tool", "tool_call_id": tc.id, "content": result})
                    else:
                        await ws.send_text(msg.content or "")
                        break

            except Exception as e:
                logger.error(f"AGI [{provider}] error: {e}")
                await ws.send_text(f"[Error AGI {provider}: {e}]")

            await ws.send_json({"done": True, "code": 0, "provider": provider, "model": use_model})

    except WebSocketDisconnect:
        pass
    except Exception as e:
        logger.error(f"AGI WS error: {e}")
