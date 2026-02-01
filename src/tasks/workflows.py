import time
import uuid
import json
import logging
import boto3
from botocore.exceptions import ClientError

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
    bucket = "results"

    s3 = boto3.client(
        "s3",
        endpoint_url=settings.s3_url,
        aws_access_key_id="accessKey",
        aws_secret_access_key="secretKey",
        region_name="us-east-1"
    )

    # Create bucket if it doesn't exist
    try:
        s3.head_bucket(Bucket=bucket)
    except ClientError:
        s3.create_bucket(Bucket=bucket)
        logging.info(f"Created bucket: {bucket}")

    # Upload file
    data = json.dumps({"result": result})
    s3.put_object(
        Bucket=bucket,
        Key=filename,
        Body=data,
        ContentType="application/json"
    )

    logging.info(f"Uploaded to s3://{bucket}/{filename}")
    return f"Uploaded to s3://{bucket}/{filename}"

@celery.task
def workflow_example(a, b):
    """Example workflow: (a + b) -> (result * 10)"""
    from celery import chain

    filename = ".".join((str(uuid.uuid4()), "txt"))

    workflow = chain(add.s(a, b), multiply.s(10), save_to_seaweed.s(filename))
    return workflow.apply_async().id