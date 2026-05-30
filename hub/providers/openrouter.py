from openai import OpenAI
from typing import AsyncIterator, Optional
from core.config import settings

OPENROUTER_BASE = "https://openrouter.ai/api/v1"
DEFAULT_MODEL = "meta-llama/llama-3.3-70b-instruct:free"


async def stream_openrouter(messages: list, model: str = DEFAULT_MODEL, api_key: Optional[str] = None) -> AsyncIterator[str]:
    key = (api_key or settings.openrouter_api_key).strip()
    if not key:
        yield "[OpenRouter API key no configurada]"
        return
    try:
        client = OpenAI(
            api_key=key,
            base_url=OPENROUTER_BASE,
            default_headers={"HTTP-Referer": "http://localhost:3000", "X-Title": "Antigravity AI"},
        )
        stream = client.chat.completions.create(model=model, messages=messages, stream=True)
        for chunk in stream:
            delta = chunk.choices[0].delta.content
            if delta:
                yield delta
    except Exception as e:
        yield f"[Error OpenRouter: {e}]"
