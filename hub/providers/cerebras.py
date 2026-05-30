from openai import OpenAI
from typing import AsyncIterator, Optional
from core.config import settings


async def stream_cerebras(messages: list, model: str = "llama3.1-8b", api_key: Optional[str] = None) -> AsyncIterator[str]:
    key = (api_key or settings.cerebras_api_key).strip()
    if not key:
        yield "[Cerebras API key no configurada]"
        return
    try:
        client = OpenAI(api_key=key, base_url="https://api.cerebras.ai/v1")
        stream = client.chat.completions.create(model=model, messages=messages, stream=True)
        for chunk in stream:
            delta = chunk.choices[0].delta.content
            if delta:
                yield delta
    except Exception as e:
        yield f"[Error Cerebras: {e}]"
