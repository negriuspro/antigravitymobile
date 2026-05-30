from fastapi import APIRouter
from core.config import settings

router = APIRouter()


@router.get("/providers/status")
def providers_status():
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
