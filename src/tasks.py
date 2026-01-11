from src.celery import celery
import time
import logging

@celery.task(bind=True, autoretry_for=(Exception,), retry_backoff=5, retry_kwargs={"max_retries": 3})
def add(self, x, y):
    result = x + y
    logging.info(f"add({x}, {y}) = {result}")
    return result

@celery.task
def multiply(x, y):
    result = x * y
    logging.info(f"multiply({x}, {y}) = {result}")
    return result

@celery.task
def workflow_example(a, b):
    from celery import chain
    workflow = chain(add.s(a, b), multiply.s(10))
    return workflow.apply_async().id
