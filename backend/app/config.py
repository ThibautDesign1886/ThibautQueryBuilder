"""
Application configuration.

All settings are read from environment variables (or a local .env file) so
that no secrets or connection details are ever hard-coded. See `.env.example`
for the full list of supported variables.
"""
from functools import lru_cache
from typing import List

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # --- SQL Server connection -------------------------------------------------
    db_driver: str = "ODBC Driver 18 for SQL Server"
    db_server: str = "localhost"
    db_port: int = 1433
    db_name: str = "ReportingDB"
    db_user: str = "sa"
    db_password: str = ""
    db_trust_server_certificate: str = "yes"
    db_encrypt: str = "yes"

    # --- Application -----------------------------------------------------------
    metadata_config_path: str = "metadata_config.json"
    preview_row_limit: int = 100
    export_row_limit: int = 500000
    # Templates are persisted to dbo.report_templates in SQL Server.
    # The DB user needs SELECT, INSERT, UPDATE on that table.
    cors_origins: str = "http://localhost:5173,http://127.0.0.1:5173"
    # Application Insights connection string. Leave blank to disable telemetry
    # (local dev). Set via APPLICATIONINSIGHTS_CONNECTION_STRING env var in prod.
    applicationinsights_connection_string: str = ""
    # Auth mode:
    #   "open"     — no auth (local dev)
    #   "password" — shared X-App-Password header (set APP_PASSWORD)
    #   "azure_ad" — Azure AD via App Service EasyAuth (set in production)
    auth_mode: str = "open"
    # Shared password used when auth_mode = "password".
    app_password: str = ""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def cors_origin_list(self) -> List[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def odbc_connection_string(self) -> str:
        """Build a pyodbc-compatible connection string from the settings."""
        return (
            f"DRIVER={{{self.db_driver}}};"
            f"SERVER={self.db_server},{self.db_port};"
            f"DATABASE={self.db_name};"
            f"UID={self.db_user};"
            f"PWD={self.db_password};"
            f"Encrypt={self.db_encrypt};"
            f"TrustServerCertificate={self.db_trust_server_certificate};"
        )


@lru_cache
def get_settings() -> Settings:
    """Cached accessor so the .env file is only parsed once."""
    return Settings()
