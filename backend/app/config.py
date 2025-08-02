from pydantic import BaseSettings


class Settings(BaseSettings):
    """Application configuration pulled from environment variables or .env file."""

    gcp_project_id: str
    gcp_bucket_name: str

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()