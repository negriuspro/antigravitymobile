import logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(message)s")

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routes.health import router as health_router
from routes.chat import router as chat_router
from routes.daniel import router as daniel_router
from routes.claude_code import router as claude_code_router
from routes.servers import router as servers_router
from routes.agi_agent import router as agi_agent_router
from routes.files import router as files_router
from routes.providers import router as providers_router
from core.config import settings

app = FastAPI(title="Antigravity Hub", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health_router)
app.include_router(chat_router)
app.include_router(daniel_router)
app.include_router(claude_code_router)
app.include_router(servers_router)
app.include_router(agi_agent_router)
app.include_router(files_router)
app.include_router(providers_router)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host=settings.hub_host, port=settings.hub_port, reload=True)
