from fastapi import FastAPI
from src.api.routers import workflows


app = FastAPI(title="Celery Workflows API")
app.include_router(workflows.router)
