import os
from celery import Celery

from config import settings


celery = Celery(
    "celery",
    broker=settings.broker_url,
    backend=settings.result_backend,
    include=["src.tasks"],
)


celery.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
)
