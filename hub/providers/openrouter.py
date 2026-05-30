import os
from openai import AsyncOpenAI
from typing import AsyncIterator, Optional
from core.config import settings

OPENROUTER_BASE = "https://openrouter.ai/api/v1"
DEFAULT_MODEL = "meta-llama/llama-3.3-70b-instruct:free"


async def stream_openrouter(
    messages: list,
    model: str = DEFAULT_MODEL,
    api_key: Optional[str] = None,
) -> AsyncIterator[str]:
    key = (api_key or settings.openrouter_api_key or "").strip()
    if not key:
        yield "[OpenRouter API key no configurada]"
        return
    app_url = os.environ.get("APP_BASE_URL", settings.app_base_url)
    try:
        client = AsyncOpenAI(
            api_key=key,
            base_url=OPENROUTER_BASE,
            default_headers={"HTTP-Referer": app_url, "X-Title": "Antigravity AI"},
        )
        stream = await client.chat.completions.create(
            model=model, messages=messages, stream=True
        )
        async for chunk in stream:
            delta = chunk.choices[0].delta.content
            if delta:
                yield delta
    except Exception as e:
        yield f"[Error OpenRouter: {e}]"
