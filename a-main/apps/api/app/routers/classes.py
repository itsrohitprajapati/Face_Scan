"""Class memberships and teacher-owned camera configuration routes."""

from __future__ import annotations

import secrets
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import (
    AttendanceSession,
    CameraSource,
    ClassMembership,
    Classroom,
    SessionStatus,
    Sighting,
    User,
    UserRole,
)
from app.schemas import (
    CameraSourceCreate,
    CameraSourceResponse,
    CameraSourceUpdate,
    ClassroomCreate,
    ClassroomResponse,
    JoinClassRequest,
)
from app.security import CurrentUser, require_role

router = APIRouter(prefix="/classes", tags=["classes"])
DbSession = Annotated[Session, Depends(get_db)]
TeacherUser = Annotated[User, Depends(require_role(UserRole.TEACHER))]
StudentUser = Annotated[User, Depends(require_role(UserRole.STUDENT))]


def serialize_classroom(classroom: Classroom) -> ClassroomResponse:
    return ClassroomResponse(
        id=classroom.id,
        name=classroom.name,
        section=classroom.section,
        join_code=classroom.join_code,
        teacher_name=classroom.teacher.full_name,
        created_at=classroom.created_at,
    )


def serialize_camera(source: CameraSource) -> CameraSourceResponse:
    return CameraSourceResponse(
        id=source.id,
        label=source.label,
        source_type=source.source_type,
        source=source.source,
        is_enabled=source.is_enabled,
        created_at=source.created_at,
        updated_at=source.updated_at,
    )


def get_owned_classroom(class_id: UUID, teacher: User, db: Session) -> Classroom:
    classroom = db.scalar(select(Classroom).where(Classroom.id == class_id, Classroom.teacher_id == teacher.id))
    if classroom is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Class not found.")
    return classroom


def generate_join_code() -> str:
    return secrets.token_urlsafe(6).upper().replace("-", "").replace("_", "")[:8]


@router.post("", response_model=ClassroomResponse, status_code=status.HTTP_201_CREATED)
def create_classroom(payload: ClassroomCreate, teacher: TeacherUser, db: DbSession) -> ClassroomResponse:
    classroom = Classroom(
        teacher_id=teacher.id,
        name=payload.name.strip(),
        section=payload.section.strip() if payload.section else None,
        join_code=generate_join_code(),
    )
    db.add(classroom)
    try:
        db.commit()
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Could not create a unique join code.") from error
    db.refresh(classroom)
    return serialize_classroom(classroom)


@router.get("", response_model=list[ClassroomResponse])
def list_classrooms(current_user: CurrentUser, db: DbSession) -> list[ClassroomResponse]:
    if current_user.role is UserRole.TEACHER:
        classrooms = db.scalars(
            select(Classroom).where(Classroom.teacher_id == current_user.id).order_by(Classroom.created_at.desc())
        ).all()
    else:
        classrooms = db.scalars(
            select(Classroom)
            .join(ClassMembership, ClassMembership.class_id == Classroom.id)
            .where(ClassMembership.student_id == current_user.id)
            .order_by(Classroom.created_at.desc())
        ).all()
    return [serialize_classroom(classroom) for classroom in classrooms]


@router.post("/join", response_model=ClassroomResponse, status_code=status.HTTP_201_CREATED)
def join_classroom(payload: JoinClassRequest, student: StudentUser, db: DbSession) -> ClassroomResponse:
    classroom = db.scalar(
        select(Classroom).where(Classroom.join_code == payload.join_code.strip().upper(), Classroom.is_active.is_(True))
    )
    if classroom is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invalid or inactive class code.")

    membership = ClassMembership(class_id=classroom.id, student_id=student.id)
    db.add(membership)
    try:
        db.commit()
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="You have already joined this class.") from error
    return serialize_classroom(classroom)


@router.get("/{class_id}/camera-sources", response_model=list[CameraSourceResponse])
def list_camera_sources(class_id: UUID, teacher: TeacherUser, db: DbSession) -> list[CameraSourceResponse]:
    get_owned_classroom(class_id, teacher, db)
    sources = db.scalars(
        select(CameraSource).where(CameraSource.class_id == class_id).order_by(CameraSource.created_at)
    ).all()
    return [serialize_camera(source) for source in sources]


@router.post(
    "/{class_id}/camera-sources",
    response_model=CameraSourceResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_camera_source(
    class_id: UUID, payload: CameraSourceCreate, teacher: TeacherUser, db: DbSession
) -> CameraSourceResponse:
    get_owned_classroom(class_id, teacher, db)
    source = CameraSource(
        class_id=class_id,
        label=payload.label.strip(),
        source_type=payload.source_type,
        source=payload.source.strip(),
    )
    db.add(source)
    db.commit()
    db.refresh(source)
    return serialize_camera(source)


@router.delete("/{class_id}/camera-sources/{source_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_camera_source(class_id: UUID, source_id: UUID, teacher: TeacherUser, db: DbSession) -> Response:
    """Delete an unused camera configuration without destroying attendance audit data."""
    get_owned_classroom(class_id, teacher, db)
    source = db.scalar(select(CameraSource).where(CameraSource.id == source_id, CameraSource.class_id == class_id))
    if source is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Camera source not found.")
    active_session = db.scalar(
        select(AttendanceSession.id).where(
            AttendanceSession.class_id == class_id,
            AttendanceSession.status == SessionStatus.ACTIVE,
        )
    )
    if active_session is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Stop the active attendance session before deleting a camera source.")
    has_sightings = db.scalar(select(Sighting.id).where(Sighting.camera_source_id == source_id).limit(1))
    if has_sightings is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This source has attendance history. Disable it instead to preserve the audit trail.")
    db.delete(source)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.patch("/{class_id}/camera-sources/{source_id}", response_model=CameraSourceResponse)
def update_camera_source(
    class_id: UUID,
    source_id: UUID,
    payload: CameraSourceUpdate,
    teacher: TeacherUser,
    db: DbSession,
) -> CameraSourceResponse:
    get_owned_classroom(class_id, teacher, db)
    source = db.scalar(select(CameraSource).where(CameraSource.id == source_id, CameraSource.class_id == class_id))
    if source is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Camera source not found.")

    updates = payload.model_dump(exclude_unset=True)
    if "label" in updates:
        updates["label"] = updates["label"].strip()
    if "source" in updates:
        updates["source"] = updates["source"].strip()
    for field, value in updates.items():
        setattr(source, field, value)
    db.commit()
    db.refresh(source)
    return serialize_camera(source)
