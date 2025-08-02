from pydantic_settings import BaseSettings
from typing import Optional
import os

class Settings(BaseSettings):
    # Google Cloud settings
    google_cloud_project: Optional[str] = None
    google_application_credentials: Optional[str] = None
    gcs_bucket_name: Optional[str] = None
    
    # Application settings
    app_name: str = "Padel Video Analyzer"
    debug: bool = True
    
    # Video processing settings
    max_video_size_mb: int = 500
    supported_video_formats: list = [".mp4", ".avi", ".mov", ".mkv"]
    
    # Analysis settings
    enable_shot_detection: bool = True
    enable_rally_analysis: bool = True
    enable_player_tracking: bool = True
    enable_technique_analysis: bool = True
    
    # API settings
    api_v1_str: str = "/api/v1"
    
    class Config:
        env_file = ".env"
        case_sensitive = False

settings = Settings()

# Set Google Cloud credentials if provided
if settings.google_application_credentials:
    os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = settings.google_application_credentials