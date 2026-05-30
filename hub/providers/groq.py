from openai import AsyncOpenAI
from typing import AsyncIterator, Optional
from core.config import settings


async def stream_groq(
    messages: list,
    model: str = "llama-3.3-70b-versatile",
    api_key: Optional[str] = None,
) -> AsyncIterator[str]:
    key = (api_key or settings.groq_api_key or "").strip()
    if not key:
        yield "[Groq API key no configurada]"
        return
    try:
        client = AsyncOpenAI(api_key=key, base_url="https://api.groq.com/openai/v1")
        stream = await client.chat.completions.create(
            model=model, messages=messages, stream=True
        )
        async for chunk in stream:
            delta = chunk.choices[0].delta.content
            if delta:
                yield delta
    except Exception as e:
        yield f"[Error Groq: {e}]"
