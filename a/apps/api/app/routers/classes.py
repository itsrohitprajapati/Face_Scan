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
    AttendanceOverrideEvent,
    AttendanceRecord,
    AttendanceSession,
    AttendanceStatus,
    CameraSource,
    ClassMembership,
    Classroom,
    SessionStatus,
    Sighting,
    StudentProfile,
    User,
    UserRole,
)
from app.schemas import (
    ActiveTeacherSessionResponse,
    CameraSourceCreate,
    CameraSourceResponse,
    CameraSourceUpdate,
    ClassroomCreate,
    ClassroomResponse,
    ClassStudentResponse,
    JoinClassRequest,
    StudentAttendanceEntry,
    StudentAttendanceSummary,
)
from app.security import CurrentUser, require_role
from app.services.attendance import coverage_for_record

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


@router.delete("/{class_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_classroom(class_id: UUID, teacher: TeacherUser, db: DbSession) -> Response:
    """Permanently delete a class, cascading its memberships, cameras, and session history."""
    classroom = get_owned_classroom(class_id, teacher, db)
    active_session = db.scalar(
        select(AttendanceSession.id).where(
            AttendanceSession.class_id == class_id,
            AttendanceSession.status == SessionStatus.ACTIVE,
        )
    )
    if active_session is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Stop the active attendance session before deleting this class.")
    db.delete(classroom)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/join", response_model=ClassroomResponse, status_code=status.HTTP_201_CREATED)
def join_classroom(payload: JoinClassRequest, student: StudentUser, db: DbSession) -> ClassroomResponse:
    print("joining class!!!")
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


@router.get("/active-session", response_model=ActiveTeacherSessionResponse)
def active_teacher_session(teacher: TeacherUser, db: DbSession) -> ActiveTeacherSessionResponse:
    """Report the one class currently running a live attendance session, if any.

    Lets the frontend keep the teacher on that class even across a page reload or a manually
    edited URL, since the recognition workers keep running server-side regardless of what the
    teacher is looking at.
    """
    row = db.execute(
        select(AttendanceSession.id, Classroom.id, Classroom.name)
        .join(Classroom, Classroom.id == AttendanceSession.class_id)
        .where(Classroom.teacher_id == teacher.id, AttendanceSession.status == SessionStatus.ACTIVE)
        .order_by(AttendanceSession.started_at.desc())
        .limit(1)
    ).first()
    if row is None:
        return ActiveTeacherSessionResponse()
    session_id, class_id, class_name = row
    return ActiveTeacherSessionResponse(class_id=class_id, class_name=class_name, session_id=session_id)


@router.get("/{class_id}/students", response_model=list[ClassStudentResponse])
def list_class_students(class_id: UUID, teacher: TeacherUser, db: DbSession) -> list[ClassStudentResponse]:
    """List every student enrolled in a class the teacher owns."""
    get_owned_classroom(class_id, teacher, db)
    rows = db.execute(
        select(User, StudentProfile, ClassMembership)
        .join(StudentProfile, StudentProfile.user_id == User.id)
        .join(ClassMembership, ClassMembership.student_id == User.id)
        .where(ClassMembership.class_id == class_id)
        .order_by(User.full_name)
    ).all()
    return [
        ClassStudentResponse(
            id=student.id,
            full_name=student.full_name,
            email=student.email,
            roll_number=profile.roll_number,
            joined_at=membership.joined_at,
        )
        for student, profile, membership in rows
    ]


@router.get("/{class_id}/students/{student_id}/attendance", response_model=StudentAttendanceSummary)
def student_attendance_in_class(
    class_id: UUID, student_id: UUID, teacher: TeacherUser, db: DbSession
) -> StudentAttendanceSummary:
    """Return one enrolled student's completed-session attendance history for this class only."""
    classroom = get_owned_classroom(class_id, teacher, db)
    membership = db.scalar(
        select(ClassMembership.id).where(
            ClassMembership.class_id == class_id, ClassMembership.student_id == student_id
        )
    )
    if membership is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student is not enrolled in this class.")

    rows = db.execute(
        select(AttendanceRecord, AttendanceSession)
        .join(AttendanceSession, AttendanceSession.id == AttendanceRecord.session_id)
        .where(
            AttendanceRecord.student_id == student_id,
            AttendanceSession.class_id == class_id,
            AttendanceSession.status == SessionStatus.COMPLETED,
        )
        .order_by(AttendanceSession.started_at.desc())
    ).all()
    override_rows = db.scalars(
        select(AttendanceOverrideEvent)
        .where(AttendanceOverrideEvent.student_id == student_id)
        .order_by(AttendanceOverrideEvent.created_at.desc(), AttendanceOverrideEvent.id.desc())
    ).all()
    latest_overrides: dict[UUID, AttendanceOverrideEvent] = {}
    for event in override_rows:
        latest_overrides.setdefault(event.session_id, event)

    history: list[StudentAttendanceEntry] = []
    for record, session in rows:
        effective = latest_overrides.get(record.session_id)
        observed_windows, eligible_windows, presence_percentage = coverage_for_record(
            session,
            db.scalars(
                select(Sighting).where(
                    Sighting.session_id == session.id,
                    Sighting.student_id == student_id,
                )
            ).all(),
        )
        history.append(
            StudentAttendanceEntry(
                session_id=session.id,
                class_id=classroom.id,
                class_name=classroom.name,
                session_title=session.title,
                session_started_at=session.started_at,
                session_ended_at=session.ended_at,
                automated_status=record.automated_status,
                effective_status=effective.corrected_status if effective else record.automated_status,
                qualifying_at=record.qualifying_at,
                observed_windows=observed_windows,
                eligible_windows=eligible_windows,
                presence_percentage=presence_percentage,
            )
        )

    present_sessions = sum(entry.effective_status is AttendanceStatus.PRESENT for entry in history)
    late_sessions = sum(entry.effective_status is AttendanceStatus.LATE for entry in history)
    absent_sessions = sum(entry.effective_status is AttendanceStatus.ABSENT for entry in history)
    total_sessions = len(history)
    attended_sessions = present_sessions + late_sessions
    return StudentAttendanceSummary(
        total_sessions=total_sessions,
        attended_sessions=attended_sessions,
        present_sessions=present_sessions,
        late_sessions=late_sessions,
        absent_sessions=absent_sessions,
        attendance_percentage=round(attended_sessions / total_sessions * 100, 1) if total_sessions else 0.0,
        history=history,
    )


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
