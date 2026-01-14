from fastapi import APIRouter, Depends

from src.api.deps import get_celery_app
from src.schemas.workflows import WorkflowRequest, WorkflowResponse, TaskStatus
from src.tasks.workflows import workflow_example


router = APIRouter(prefix="/workflows", tags=["workflows"])


@router.post("/", response_model=WorkflowResponse)
def trigger_workflow(
    request: WorkflowRequest,
    celery_app=Depends(get_celery_app)
):
    result = workflow_example.delay(request.a, request.b)
    return WorkflowResponse(task_id=result.id)


@router.get("/{task_id}/status", response_model=TaskStatus)
def get_task_status(
    task_id: str,
    celery_app=Depends(get_celery_app)
):
    result = celery_app.AsyncResult(task_id)
    return TaskStatus(
        task_id=task_id,
        status=result.status,
        result=result.result if result.ready() else None
    )
