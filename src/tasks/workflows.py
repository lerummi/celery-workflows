import time
import uuid
import json
import logging
import requests

from src.core.celery import celery
from src.core.config import settings


@celery.task(bind=True, autoretry_for=(Exception,), retry_backoff=5, retry_kwargs={"max_retries": 3})
def add(self, x, y):
    time.sleep(2)
    result = x + y
    logging.info(f"add({x}, {y}) = {result}")
    return result

@celery.task
def multiply(x, y):
    result = x * y
    logging.info(f"multiply({x}, {y}) = {result}")
    return result


@celery.task
def save_to_seaweed(result: str, filename: str):
    path = f"/results/{filename}"
    url = f"{settings.filer_url}{path}"

    data = json.dumps({"result": result}).encode("utf-8")

    files = {"file": (filename, data, "application/json")}

    response = requests.post(url, files=files)
    response.raise_for_status()

    logging.info(f"Uploaded to {path}")
    return f"Uploaded to {path}"

@celery.task
def workflow_example(a, b):
    """Example workflow: (a + b) -> (result * 10)"""
    from celery import chain

    filename = ".".join((str(uuid.uuid4()), "txt"))

    workflow = chain(add.s(a, b), multiply.s(10), save_to_seaweed.s(filename))
    return workflow.apply_async().id