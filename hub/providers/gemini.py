import asyncio
import base64
from google import genai
from google.genai import types
from typing import AsyncIterator, Optional
from core.config import settings


async def stream_gemini(
    messages: list,
    model: str = "gemini-2.0-flash",
    thinking_budget: Optional[int] = None,
    image: Optional[str] = None,
    image_mime: str = "image/jpeg",
    api_key: Optional[str] = None,
) -> AsyncIterator[str]:
    key = (api_key or settings.gemini_api_key or "").strip()
    if not key:
        yield "[Gemini API key no configurada]"
        return

    def _sync_call() -> str:
        client = genai.Client(api_key=key)
        contents = []
        for m in messages[:-1]:
            role = "user" if m["role"] == "user" else "model"
            contents.append(types.Content(role=role, parts=[types.Part(text=m["content"])]))

        last = messages[-1] if messages else None
        if last:
            parts = []
            if last.get("content"):
                parts.append(types.Part(text=last["content"]))
            if image:
                raw = image.split(",")[-1]
                img_bytes = base64.b64decode(raw)
                parts.append(types.Part(inline_data=types.Blob(mime_type=image_mime, data=img_bytes)))
            role = "user" if last["role"] == "user" else "model"
            contents.append(types.Content(role=role, parts=parts))

        config_kwargs = {}
        if thinking_budget and thinking_budget > 0:
            config_kwargs["thinking_config"] = types.ThinkingConfig(thinking_budget=thinking_budget)

        response = client.models.generate_content(
            model=model,
            contents=contents if contents else "\n".join(f"{m['role']}: {m['content']}" for m in messages),
            config=types.GenerateContentConfig(**config_kwargs) if config_kwargs else None,
        )
        return response.text or ""

    try:
        text = await asyncio.to_thread(_sync_call)
        yield text
    except Exception as e:
        yield f"[Error Gemini: {e}]"
