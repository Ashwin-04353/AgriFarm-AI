from pydantic_settings import BaseSettings
from functools import lru_cache

class Settings(BaseSettings):
    db_server: str
    db_name: str
    db_driver: str = "ODBC Driver 18 for SQL Server"
    db_trusted_connection: str = "yes"
    db_user: str = ""
    db_password: str = ""
    secret_key: str
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 7
    groq_api_key: str
    app_env: str = "development"
    app_host: str = "0.0.0.0"
    app_port: int = 8000
    allowed_origins: str = "http://127.0.0.1:5500"
    rate_limit_per_minute: int = 60
    max_csv_size_mb: int = 10
    upload_dir: str = "./uploads"

    class Config:
        env_file = ".env"

@lru_cache
def get_settings():
    return Settings()