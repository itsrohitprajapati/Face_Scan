"""FastAPI application entry point."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.utils import get_openapi

from app.config import settings
from app.database import (
    Base,
    engine,
    ensure_anonymous_sightings_compatible,
    ensure_room_schema_compatible,
)
from app.routers import admin, auth, classes, sessions
from app.services.recognition import recognition_manager


@asynccontextmanager
async def lifespan(_: FastAPI):
    settings.media_root.mkdir(parents=True, exist_ok=True)
    Base.metadata.create_all(bind=engine)
    ensure_anonymous_sightings_compatible()
    ensure_room_schema_compatible()
    yield
    recognition_manager.stop_all()


app = FastAPI(title="Smart Classroom Attendance API", version="0.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(admin.router, prefix="/api/v1")
app.include_router(auth.router, prefix="/api/v1")
app.include_router(classes.router, prefix="/api/v1")
app.include_router(sessions.router, prefix="/api/v1")


def custom_openapi() -> dict:
    """Describe multipart enrollment photos as binary files for Swagger UI."""
    if app.openapi_schema:
        return app.openapi_schema

    schema = get_openapi(title=app.title, version=app.version, routes=app.routes)
    body = schema["components"]["schemas"]["Body_register_student_api_v1_auth_register_student_post"]
    body["properties"]["photos"]["items"] = {"type": "string", "format": "binary"}
    app.openapi_schema = schema
    return app.openapi_schema


app.openapi = custom_openapi


@app.get("/health")
def health_check() -> dict[str, str]:
    return {"status": "ok"}
