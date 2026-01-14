from pydantic import BaseModel


class WorkflowRequest(BaseModel):
    a: int
    b: int


class WorkflowResponse(BaseModel):
    task_id: str


class TaskStatus(BaseModel):
    task_id: str
    status: str
    result: str | None = None