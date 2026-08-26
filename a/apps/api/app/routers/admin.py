"""Admin-owned physical room and camera configuration."""

import secrets
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import (
    AttendanceSession,
    CameraSource,
    Room,
    SessionStatus,
    Sighting,
    User,
    UserRole,
)
from app.schemas import (
    CameraSourceResponse,
    RoomCameraCreate,
    RoomCameraUpdate,
    RoomCreate,
    RoomResponse,
    RoomUpdate,
)
from app.security import require_role

router = APIRouter(prefix="/admin/rooms", tags=["admin rooms"])
DbSession = Annotated[Session, Depends(get_db)]
AdminUser = Annotated[User, Depends(require_role(UserRole.ADMIN))]


def generate_room_code() -> str:
    return secrets.token_urlsafe(6).upper().replace("-", "").replace("_", "")[:8]


def serialize_camera(camera: CameraSource) -> CameraSourceResponse:
    return CameraSourceResponse(id=camera.id, label=camera.label, source_type=camera.source_type, source=camera.source, is_enabled=camera.is_enabled, created_at=camera.created_at, updated_at=camera.updated_at)


def serialize_room(room: Room, db: Session) -> RoomResponse:
    cameras = db.scalars(select(CameraSource).where(CameraSource.room_id == room.id)).all()
    active = db.scalar(select(AttendanceSession).where(AttendanceSession.room_id == room.id, AttendanceSession.status == SessionStatus.ACTIVE))
    return RoomResponse(id=room.id, name=room.name, room_code=room.room_code, is_active=room.is_active, camera_count=len(cameras), enabled_camera_count=sum(camera.is_enabled for camera in cameras), active_session_id=active.id if active else None, active_session_title=active.title if active else None, created_at=room.created_at)


def get_room(room_id: UUID, db: Session) -> Room:
    room = db.get(Room, room_id)
    if room is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Room not found.")
    return room


@router.get("", response_model=list[RoomResponse])
def list_rooms(_admin: AdminUser, db: DbSession) -> list[RoomResponse]:
    return [serialize_room(room, db) for room in db.scalars(select(Room).order_by(Room.name)).all()]


@router.post("", response_model=RoomResponse, status_code=status.HTTP_201_CREATED)
def create_room(payload: RoomCreate, _admin: AdminUser, db: DbSession) -> RoomResponse:
    room = Room(name=payload.name.strip(), room_code=generate_room_code())
    db.add(room)
    try:
        db.commit()
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="A room already uses this name or code.") from error
    db.refresh(room)
    return serialize_room(room, db)


@router.patch("/{room_id}", response_model=RoomResponse)
def update_room(room_id: UUID, payload: RoomUpdate, _admin: AdminUser, db: DbSession) -> RoomResponse:
    room = get_room(room_id, db)
    updates = payload.model_dump(exclude_unset=True)
    if "name" in updates:
        updates["name"] = updates["name"].strip()
    for key, value in updates.items():
        setattr(room, key, value)
    try:
        db.commit()
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="A room already uses this name.") from error
    db.refresh(room)
    return serialize_room(room, db)


@router.post("/{room_id}/regenerate-code", response_model=RoomResponse)
def regenerate_room_code(room_id: UUID, _admin: AdminUser, db: DbSession) -> RoomResponse:
    room = get_room(room_id, db)
    room.room_code = generate_room_code()
    db.commit()
    db.refresh(room)
    return serialize_room(room, db)


@router.get("/{room_id}/cameras", response_model=list[CameraSourceResponse])
def list_room_cameras(room_id: UUID, _admin: AdminUser, db: DbSession) -> list[CameraSourceResponse]:
    get_room(room_id, db)
    cameras = db.scalars(select(CameraSource).where(CameraSource.room_id == room_id).order_by(CameraSource.created_at)).all()
    return [serialize_camera(camera) for camera in cameras]


@router.post("/{room_id}/cameras", response_model=CameraSourceResponse, status_code=status.HTTP_201_CREATED)
def create_room_camera(room_id: UUID, payload: RoomCameraCreate, _admin: AdminUser, db: DbSession) -> CameraSourceResponse:
    get_room(room_id, db)
    camera = CameraSource(room_id=room_id, class_id=None, label=payload.label.strip(), source_type=payload.source_type, source=payload.source.strip())
    db.add(camera)
    db.commit()
    db.refresh(camera)
    return serialize_camera(camera)


@router.patch("/{room_id}/cameras/{camera_id}", response_model=CameraSourceResponse)
def update_room_camera(room_id: UUID, camera_id: UUID, payload: RoomCameraUpdate, _admin: AdminUser, db: DbSession) -> CameraSourceResponse:
    camera = db.scalar(select(CameraSource).where(CameraSource.id == camera_id, CameraSource.room_id == room_id))
    if camera is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Camera source not found.")
    if db.scalar(select(AttendanceSession.id).where(AttendanceSession.room_id == room_id, AttendanceSession.status == SessionStatus.ACTIVE)):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Stop the active room session before changing cameras.")
    updates = payload.model_dump(exclude_unset=True)
    for key in ("label", "source"):
        if key in updates:
            updates[key] = updates[key].strip()
    for key, value in updates.items():
        setattr(camera, key, value)
    db.commit()
    db.refresh(camera)
    return serialize_camera(camera)


@router.delete("/{room_id}/cameras/{camera_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_room_camera(room_id: UUID, camera_id: UUID, _admin: AdminUser, db: DbSession) -> None:
    camera = db.scalar(select(CameraSource).where(CameraSource.id == camera_id, CameraSource.room_id == room_id))
    if camera is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Camera source not found.")
    if db.scalar(select(AttendanceSession.id).where(AttendanceSession.room_id == room_id, AttendanceSession.status == SessionStatus.ACTIVE)):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Stop the active room session before deleting cameras.")
    if db.scalar(select(Sighting.id).where(Sighting.camera_source_id == camera_id).limit(1)):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This camera has attendance history. Disable it instead.")
    db.delete(camera)
    db.commit()
