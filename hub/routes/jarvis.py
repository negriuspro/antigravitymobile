from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from providers.anthropic import stream_claude

router = APIRouter()


class JarvisCommand(BaseModel):
    text: str
    context: str = "antigravity"


@router.post("/jarvis")
async def jarvis_command(cmd: JarvisCommand):
    """
    Jarvis envia el texto del comando aqui cuando escucha 'antigravity'.
    El Hub lo procesa con Claude y devuelve la respuesta.
    """
    if not cmd.text.strip():
        raise HTTPException(status_code=400, detail="Comando vacio")

    system_prompt = (
        "Eres el asistente IA de Antigravity. "
        "El usuario envio este comando por voz via Jarvis. "
        "Ejecuta la tarea o responde de forma clara y concisa."
    )
    messages = [
        {"role": "user", "content": cmd.text}
    ]

    response_text = ""
    async for chunk in stream_claude(messages):
        response_text += chunk

    return {"status": "ok", "command": cmd.text, "response": response_text}
