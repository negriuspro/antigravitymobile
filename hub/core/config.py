from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    anthropic_api_key: str = ""
    gemini_api_key: str = ""
    groq_api_key: str = ""
    cerebras_api_key: str = ""
    openai_api_key: str = ""
    sambanova_api_key: str = ""
    openrouter_api_key: str = ""
    hub_host: str = "0.0.0.0"
    hub_port: int = 8000
    redis_url: str = "redis://redis:6379/0"
    docker_allowed_label: str = "com.antigravity.manage=true"
    files_base_path: str = "/data/files"
    app_base_url: str = "http://localhost:3000"

    class Config:
        env_file = ".env"


settings = Settings()
