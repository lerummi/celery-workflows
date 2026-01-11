from fastapi import FastAPI
from pydantic import BaseModel

from src.tasks import workflow_example   # reuse your existing task

app = FastAPI()


class WorkflowRequest(BaseModel):
    a: int
    b: int


class WorkflowResponse(BaseModel):
    task_id: str


@app.post("/workflow", response_model=WorkflowResponse)
def trigger_workflow(body: WorkflowRequest):
    """
    Trigger the Celery workflow_example(a, b) via HTTP.
    """
    async_result = workflow_example.delay(body.a, body.b)
    return WorkflowResponse(task_id=async_result.id)
