from pathlib import Path
from celery import Celery

from src.core.config import settings


task_modules = [
    f.with_suffix("").as_posix().replace("/", ".")  # Clean conversion
    for f in Path("src/tasks").rglob("*.py")
    if f.name != '__init__.py'
]


celery = Celery(
    "celery",
    broker=settings.broker_url,
    backend=settings.result_backend,
    include=task_modules
)


celery.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
)
