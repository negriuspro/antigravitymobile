from fastapi import APIRouter
from core.config import settings
from core.claude_collector import collect as collect_claude_metrics
from providers.models import MODELS

router = APIRouter()

_LABELS = {
    "groq": "Groq",
    "cerebras": "Cerebras",
    "gemini": "Gemini",
    "openrouter": "OpenRouter",
    "claude": "Claude Chat",
    "claude_code": "Claude Code",
    "sambanova": "SambaNova",
}


def _configured_map() -> dict[str, bool]:
    """Returns which providers have API keys configured."""
    return {
        "groq": bool(settings.groq_api_key.strip()),
        "cerebras": bool(settings.cerebras_api_key.strip()),
        "gemini": bool(settings.gemini_api_key.strip()),
        "openrouter": bool(settings.openrouter_api_key.strip()),
        "claude": bool(settings.anthropic_api_key.strip()),
        "claude_code": True,
        "sambanova": bool(settings.sambanova_api_key.strip()),
    }


@router.get("/providers/status")
def providers_status():
    return _configured_map()


@router.get("/providers/claude/metrics")
def claude_code_metrics():
    """Returns local Claude Code CLI usage stats read from ~/.claude/projects/*.jsonl."""
    snap = collect_claude_metrics()
    return {
        "has_data": snap.has_data,
        "session": snap.session,
        "today": snap.today,
        "sparkline": snap.sparkline,
    }


@router.get("/providers/metrics")
def providers_metrics():
    """Returns provider health and available models for the agents-style dashboard."""
    return [
        {
            "provider_id": provider_id,
            "label": _LABELS[provider_id],
            "health": "ok" if is_configured else "not_configured",
            "models": MODELS.get(provider_id, []),
        }
        for provider_id, is_configured in _configured_map().items()
    ]
