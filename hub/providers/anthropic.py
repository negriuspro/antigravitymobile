from typing import AsyncIterator
from core.config import settings


async def stream_claude(
    messages: list,
    model: str = "claude-sonnet-4-6",
    api_key: str = "",
) -> AsyncIterator[str]:
    key = (api_key or settings.anthropic_api_key or "").strip()

    if not key or key.startswith("sk-ant-..."):
        yield "[Claude disabled: configure ANTHROPIC_API_KEY. CLI fallback is disabled in Docker mode.]"
        return

    try:
        from anthropic import AsyncAnthropic
        client = AsyncAnthropic(api_key=key)
        async with client.messages.stream(
            model=model,
            max_tokens=4096,
            messages=messages,
        ) as stream:
            async for text in stream.text_stream:
                yield text
    except Exception as e:
        yield f"[Error API Claude: {e}]"
