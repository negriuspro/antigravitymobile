from openai import AsyncOpenAI
from typing import AsyncIterator
from core.config import settings


async def stream_codex(messages: list, model: str = "gpt-4o") -> AsyncIterator[str]:
    client = AsyncOpenAI(api_key=settings.openai_api_key)
    stream = await client.chat.completions.create(
        model=model,
        messages=messages,
        stream=True,
    )
    async for chunk in stream:
        delta = chunk.choices[0].delta.content
        if delta:
            yield delta
