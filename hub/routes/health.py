from fastapi import APIRouter
from datetime import datetime
from providers.models import MODELS

router = APIRouter()

@router.get("/health")
async def health():
    return {
        "status": "online",
        "system": "Antigravity Hub",
        "timestamp": datetime.utcnow().isoformat(),
    }

@router.get("/models")
async def get_models():
    return {"models": MODELS}
