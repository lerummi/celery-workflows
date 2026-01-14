from pydantic import Field
from pydantic_settings import BaseSettings


class CelerySettings(BaseSettings):

    broker_url: str = Field(
        default="redis://localhost:6379/0",
        alias="CELERY_BROKER_URL"
    )

    result_backend: str = Field(
        default="redis://localhost:6379/1",
        alias="CELERY_RESULT_BACKEND"
    )

settings = CelerySettings()
