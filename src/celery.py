import os
from celery import Celery


BROKER_URL = os.getenv("CELERY_BROKER_URL", "redis://localhost:6379/0")
RESULT_BACKEND = os.getenv("CELERY_RESULT_BACKEND", "redis://localhost:6379/1")


celery = Celery(
    "celery",
    broker=BROKER_URL,
    backend=RESULT_BACKEND,
    include=["src.tasks"],
)


celery.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
)
