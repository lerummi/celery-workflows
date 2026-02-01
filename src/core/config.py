from pydantic import Field
from pydantic_settings import BaseSettings


class CelerySettings(BaseSettings):

    broker_url: str = Field(
        alias="CELERY_BROKER_URL"
    )

    result_backend: str = Field(
        alias="CELERY_RESULT_BACKEND"
    )

    filer_url: str = Field(
        alias="SEAWEEDFS_FILER_URL"
    )

settings = CelerySettings()
