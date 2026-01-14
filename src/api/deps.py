from src.core.celery import celery


def get_celery_app():
    return celery
