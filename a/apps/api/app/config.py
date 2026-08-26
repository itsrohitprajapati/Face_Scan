"""Application configuration loaded from environment variables."""

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime settings for the local development application."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    database_url: str = (
        "postgresql+psycopg://attendance:attendance_dev_password@localhost:5432/"
        "smart_attendance"
    )
    jwt_secret: str = "replace-this-development-secret-before-sharing"
    teacher_invite_code: str = "SMART-TEACHER-DEMO"
    admin_invite_code: str = "SMART-ADMIN-DEMO"
    media_root: Path = Path("storage")
    cors_origins: str = "http://localhost:5173"
    access_token_expire_minutes: int = 480
    openrouter_api_key: str | None = None
    openrouter_model: str = "openai/gpt-4o-mini"
    openrouter_base_url: str = "https://openrouter.ai/api/v1"

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


settings = Settings()
