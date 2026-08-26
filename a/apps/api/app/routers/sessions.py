"""Teacher-controlled attendance-session routes."""

import json
from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, HTTPException, Response, status
from fastapi.responses import StreamingResponse
from sqlalchemy import func, select
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
    Room,
    SessionStatus,
    Sighting,
    SightingAssignment,
    StudentProfile,
    User,
    UserRole,
)
from app.routers.classes import get_owned_classroom
from app.schemas import (
    AttendanceAssistantResponse,
    AttendanceOverrideCreate,
    AttendanceOverrideResponse,
    AttendanceQueryRequest,
    AttendanceRecordResponse,
    AttendanceSessionCreate,
    AttendanceSessionResponse,
    CameraSourceResponse,
    SessionInsightsResponse,
    SightingAssignmentResponse,
    SightingResponse,
    StudentAttendanceEntry,
    StudentAttendanceSummary,
)
from app.security import require_role
from app.services.attendance import (
    calculate_attendance,
    coverage_for_record,
    status_for_sightings,
)
from app.services.attendance_assistant import answer_attendance_question
from app.services.insights import build_session_insights
from app.services.recognition import recognition_manager

router = APIRouter(tags=["attendance sessions"])
DbSession = Annotated[Session, Depends(get_db)]
TeacherUser = Annotated[User, Depends(require_role(UserRole.TEACHER))]
StudentUser = Annotated[User, Depends(require_role(UserRole.STUDENT))]


def serialize_session(session: AttendanceSession) -> AttendanceSessionResponse:
    return AttendanceSessionResponse(
        id=session.id,
        class_id=session.class_id,
        room_id=session.room_id,
        room_name=session.room.name if session.room else None,
        room_code=session.room.room_code if session.room else None,
        title=session.title,
        status=session.status,
        started_at=session.started_at,
        ended_at=session.ended_at,
        grace_period_minutes=session.grace_period_minutes,
        minimum_sightings=session.minimum_sightings,
        qualification_window_minutes=session.qualification_window_minutes,
        presence_threshold_percentage=70.0,
    )

def serialize_override(event: AttendanceOverrideEvent, teacher: User) -> AttendanceOverrideResponse:
    return AttendanceOverrideResponse(
        id=event.id,
        status=event.corrected_status,
        reason=event.reason,
        teacher_id=teacher.id,
        teacher_name=teacher.full_name,
        created_at=event.created_at,
    )


def get_owned_session(session_id: UUID, teacher: User, db: Session) -> AttendanceSession:
    session = db.scalar(
        select(AttendanceSession)
        .join(Classroom, Classroom.id == AttendanceSession.class_id)
        .where(AttendanceSession.id == session_id, Classroom.teacher_id == teacher.id)
    )
    if session is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Attendance session not found.")
    return session


@router.get("/teacher/rooms/{room_code}/cameras", response_model=list[CameraSourceResponse])
def teacher_room_cameras(room_code: str, _teacher: TeacherUser, db: DbSession) -> list[CameraSourceResponse]:
    room = db.scalar(
        select(Room).where(
            (func.lower(Room.room_code) == room_code.strip().lower())
            | (func.lower(Room.name) == room_code.strip().lower()),
            Room.is_active.is_(True),
        )
    )
    if room is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invalid or inactive room code.")
    cameras = db.scalars(select(CameraSource).where(CameraSource.room_id == room.id, CameraSource.is_enabled.is_(True)).order_by(CameraSource.created_at)).all()
    return [CameraSourceResponse(id=camera.id, label=camera.label, source_type=camera.source_type, source=camera.source, is_enabled=camera.is_enabled, created_at=camera.created_at, updated_at=camera.updated_at) for camera in cameras]
@router.post(
    "/classes/{class_id}/sessions",
    response_model=AttendanceSessionResponse,
    status_code=status.HTTP_201_CREATED,
)
def start_session(
    class_id: UUID, payload: AttendanceSessionCreate, teacher: TeacherUser, db: DbSession
) -> AttendanceSessionResponse:
    classroom = get_owned_classroom(class_id, teacher, db)
    existing = db.scalar(
        select(AttendanceSession.id).where(AttendanceSession.class_id == class_id, AttendanceSession.status == SessionStatus.ACTIVE)
    )
    if existing is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This class already has an active session.")
    room = db.scalar(
        select(Room).where(
            (func.lower(Room.room_code) == payload.room_code.strip().lower())
            | (func.lower(Room.name) == payload.room_code.strip().lower()),
            Room.is_active.is_(True),
        )
    )
    if room is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invalid or inactive room code.")
    room_in_use = db.scalar(
        select(AttendanceSession.id).where(
            AttendanceSession.room_id == room.id,
            AttendanceSession.status == SessionStatus.ACTIVE,
        )
    )
    if room_in_use is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This room already has an active attendance session.")
    enabled_camera_count = db.scalar(
        select(CameraSource.id).where(CameraSource.room_id == room.id, CameraSource.is_enabled.is_(True)).limit(1)
    )
    if enabled_camera_count is None:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="This room has no enabled camera sources.")

    session = AttendanceSession(
        class_id=classroom.id,
        room_id=room.id,
        title=payload.title.strip(),
        started_at=datetime.now(UTC),
        grace_period_minutes=payload.grace_period_minutes,
        minimum_sightings=payload.minimum_sightings,
        qualification_window_minutes=payload.qualification_window_minutes,
    )
    db.add(session)
    db.commit()
    db.refresh(session)
    recognition_manager.start_session(session.id)
    return serialize_session(session)


@router.post("/sessions/{session_id}/stop", response_model=AttendanceSessionResponse)
def stop_session(session_id: UUID, teacher: TeacherUser, db: DbSession) -> AttendanceSessionResponse:
    session = get_owned_session(session_id, teacher, db)
    if session.status is SessionStatus.COMPLETED:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This session is already completed.")
    recognition_manager.stop_session(session.id)
    session.status = SessionStatus.COMPLETED
    session.ended_at = datetime.now(UTC)
    db.commit()
    db.refresh(session)
    calculate_attendance(session, db)
    return serialize_session(session)


@router.get("/classes/{class_id}/sessions", response_model=list[AttendanceSessionResponse])
def list_sessions(class_id: UUID, teacher: TeacherUser, db: DbSession) -> list[AttendanceSessionResponse]:
    get_owned_classroom(class_id, teacher, db)
    sessions = db.scalars(
        select(AttendanceSession).where(AttendanceSession.class_id == class_id).order_by(AttendanceSession.started_at.desc())
    ).all()
    return [serialize_session(session) for session in sessions]


@router.get("/sessions/{session_id}/attendance", response_model=list[AttendanceRecordResponse])
def list_attendance_records(
    session_id: UUID, teacher: TeacherUser, db: DbSession
) -> list[AttendanceRecordResponse]:
    session = get_owned_session(session_id, teacher, db)
    rows = db.execute(
        select(AttendanceRecord, User, StudentProfile)
        .join(User, User.id == AttendanceRecord.student_id)
        .join(StudentProfile, StudentProfile.user_id == User.id)
        .where(AttendanceRecord.session_id == session_id)
        .order_by(User.full_name)
    ).all()
    override_rows = db.execute(
        select(AttendanceOverrideEvent, User)
        .join(User, User.id == AttendanceOverrideEvent.teacher_id)
        .where(AttendanceOverrideEvent.session_id == session_id)
        .order_by(AttendanceOverrideEvent.created_at.desc(), AttendanceOverrideEvent.id.desc())
    ).all()
    overrides_by_student: dict[UUID, list[tuple[AttendanceOverrideEvent, User]]] = {}
    for event, override_teacher in override_rows:
        overrides_by_student.setdefault(event.student_id, []).append((event, override_teacher))

    all_sightings = db.scalars(select(Sighting).where(Sighting.session_id == session_id)).all()
    assigned = {
        item.sighting_id: item.student_id
        for item in db.scalars(
            select(SightingAssignment).join(Sighting, Sighting.id == SightingAssignment.sighting_id).where(Sighting.session_id == session_id)
        ).all()
    }
    sightings_by_student: dict[UUID, list[Sighting]] = {}
    for sighting in all_sightings:
        resolved_student_id = sighting.student_id or assigned.get(sighting.id)
        if resolved_student_id is not None:
            sightings_by_student.setdefault(resolved_student_id, []).append(sighting)

    responses: list[AttendanceRecordResponse] = []
    for record, student, profile in rows:
        override_history = overrides_by_student.get(student.id, [])
        latest = override_history[0] if override_history else None
        latest_override = serialize_override(*latest) if latest else None
        assigned_sightings = sightings_by_student.get(student.id, [])
        derived_status = status_for_sightings(session, assigned_sightings)
        effective_status = latest[0].corrected_status if latest else derived_status
        observed_windows, eligible_windows, presence_percentage = coverage_for_record(
            session, assigned_sightings
        )
        responses.append(
            AttendanceRecordResponse(
                student_id=student.id,
                student_name=student.full_name,
                roll_number=profile.roll_number,
                automated_status=record.automated_status,
                effective_status=effective_status,
                qualifying_at=record.qualifying_at,
                observed_windows=observed_windows,
                eligible_windows=eligible_windows,
                presence_percentage=presence_percentage,
                latest_override=latest_override,
                override_history=[
                    serialize_override(event, override_teacher)
                    for event, override_teacher in override_history
                ],
            )
        )
    return responses


@router.patch(
    "/sessions/{session_id}/attendance/{student_id}",
    response_model=AttendanceOverrideResponse,
    status_code=status.HTTP_201_CREATED,
)
def override_attendance(
    session_id: UUID,
    student_id: UUID,
    payload: AttendanceOverrideCreate,
    teacher: TeacherUser,
    db: DbSession,
) -> AttendanceOverrideResponse:
    """Append an immutable teacher correction without changing the automated result."""
    session = get_owned_session(session_id, teacher, db)
    if session.status is not SessionStatus.COMPLETED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Attendance can be corrected only after the session is completed.",
        )
    attendance_record = db.scalar(
        select(AttendanceRecord).where(
            AttendanceRecord.session_id == session_id,
            AttendanceRecord.student_id == student_id,
        )
    )
    if attendance_record is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Attendance record not found for this session and student.",
        )

    event = AttendanceOverrideEvent(
        session_id=session.id,
        student_id=student_id,
        teacher_id=teacher.id,
        corrected_status=payload.status,
        reason=payload.reason.strip() or "Teacher correction",
    )
    db.add(event)
    db.commit()
    db.refresh(event)
    return serialize_override(event, teacher)


@router.get("/sessions/{session_id}/cameras/{camera_id}/preview")
def preview_camera_frame(
    session_id: UUID, camera_id: UUID, teacher: TeacherUser, db: DbSession
) -> Response:
    session = get_owned_session(session_id, teacher, db)
    if session.status is not SessionStatus.ACTIVE:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="The attendance session is not active.")
    camera = db.scalar(
        select(CameraSource).where(
            CameraSource.id == camera_id,
            CameraSource.room_id == session.room_id,
            CameraSource.is_enabled.is_(True),
        )
    )
    if camera is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Camera source not found.")
    frame = recognition_manager.get_preview_frame(session.id, camera.id)
    if frame is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Camera frame is not ready.")
    return Response(content=frame, media_type="image/jpeg", headers={"Cache-Control": "no-store"})


@router.get("/student/attendance", response_model=StudentAttendanceSummary)
def student_attendance_history(student: StudentUser, db: DbSession) -> StudentAttendanceSummary:
    """Return only this student's completed, joined-class attendance history."""
    rows = db.execute(
        select(AttendanceRecord, AttendanceSession, Classroom)
        .join(AttendanceSession, AttendanceSession.id == AttendanceRecord.session_id)
        .join(Classroom, Classroom.id == AttendanceSession.class_id)
        .join(
            ClassMembership,
            (ClassMembership.class_id == Classroom.id)
            & (ClassMembership.student_id == student.id),
        )
        .where(
            AttendanceRecord.student_id == student.id,
            AttendanceSession.status == SessionStatus.COMPLETED,
        )
        .order_by(AttendanceSession.started_at.desc())
    ).all()
    override_rows = db.execute(
        select(AttendanceOverrideEvent)
        .where(AttendanceOverrideEvent.student_id == student.id)
        .order_by(AttendanceOverrideEvent.created_at.desc(), AttendanceOverrideEvent.id.desc())
    ).scalars().all()
    latest_overrides: dict[UUID, AttendanceOverrideEvent] = {}
    for event in override_rows:
        latest_overrides.setdefault(event.session_id, event)

    history: list[StudentAttendanceEntry] = []
    for record, session, classroom in rows:
        effective_status = latest_overrides.get(record.session_id)
        observed_windows, eligible_windows, presence_percentage = coverage_for_record(
            session,
            db.scalars(
                select(Sighting).where(
                    Sighting.session_id == session.id,
                    Sighting.student_id == student.id,
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
                effective_status=effective_status.corrected_status if effective_status else record.automated_status,
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


@router.post("/teacher/attendance-assistant", response_model=AttendanceAssistantResponse)
async def teacher_attendance_assistant(
    payload: AttendanceQueryRequest, teacher: TeacherUser, db: DbSession
) -> AttendanceAssistantResponse:
    """Interpret a teacher question with OpenRouter, then execute one bounded attendance tool."""
    classes = db.scalars(
        select(Classroom).where(Classroom.teacher_id == teacher.id).order_by(Classroom.name)
    ).all()
    if payload.class_id is not None:
        classes = [classroom for classroom in classes if classroom.id == payload.class_id]
        if not classes:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Class not found.")
    available_classes = [{"id": str(classroom.id), "name": classroom.name} for classroom in classes]
    try:
        result = await answer_attendance_question(payload.query, teacher.id, db, available_classes)
    except RuntimeError as error:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(error)) from error
    except (httpx.HTTPError, ValueError, KeyError, json.JSONDecodeError) as error:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="The attendance assistant could not complete this query.") from error
    return AttendanceAssistantResponse.model_validate(result)


@router.get("/sessions/{session_id}/insights", response_model=SessionInsightsResponse)
def session_insights(session_id: UUID, teacher: TeacherUser, db: DbSession) -> SessionInsightsResponse:
    session = get_owned_session(session_id, teacher, db)
    return SessionInsightsResponse.model_validate(build_session_insights(session, db))


@router.get("/sessions/{session_id}/report.csv")
def session_report(session_id: UUID, teacher: TeacherUser, db: DbSession) -> StreamingResponse:
    """Download a teacher-owned integrity report without exposing biometric data."""
    session = get_owned_session(session_id, teacher, db)
    insights = build_session_insights(session, db)
    rows = ["student,roll_number,automated_status,effective_status,observed_windows,eligible_windows,presence_percentage,first_seen,last_seen,review_reasons"]
    for student in insights["students"]:  # type: ignore[index]
        values = [
            str(student[key]).replace('"', '""') if student[key] is not None else ""
            for key in ("student_name", "roll_number", "automated_status", "effective_status", "observed_windows", "eligible_windows", "presence_percentage", "first_seen_at", "last_seen_at")
        ]
        values.append("; ".join(student["review_reasons"]))  # type: ignore[index]
        rows.append(",".join(f'"{value}"' for value in values))
    content = "\n".join(rows) + "\n"
    return StreamingResponse(
        iter([content]),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="attendance-{session.id}.csv"'},
    )


@router.post(
    "/sessions/{session_id}/sightings/{sighting_id}/assign/{student_id}",
    response_model=SightingAssignmentResponse,
    status_code=status.HTTP_201_CREATED,
)
def assign_unknown_sighting(
    session_id: UUID,
    sighting_id: UUID,
    student_id: UUID,
    teacher: TeacherUser,
    db: DbSession,
) -> SightingAssignmentResponse:
    """Append a teacher attribution while preserving the original anonymous event."""
    session = get_owned_session(session_id, teacher, db)
    if session.status is not SessionStatus.COMPLETED:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Unknown detections can be assigned after the session is completed.")
    sighting = db.scalar(
        select(Sighting).where(
            Sighting.id == sighting_id,
            Sighting.session_id == session.id,
            Sighting.student_id.is_(None),
        )
    )
    if sighting is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Unknown detection not found.")
    existing = db.scalar(select(SightingAssignment.id).where(SightingAssignment.sighting_id == sighting.id))
    if existing is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This detection has already been assigned.")
    student = db.scalar(
        select(User)
        .join(ClassMembership, ClassMembership.student_id == User.id)
        .where(ClassMembership.class_id == session.class_id, User.id == student_id)
    )
    if student is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student is not enrolled in this class.")
    assignment = SightingAssignment(sighting_id=sighting.id, student_id=student.id, teacher_id=teacher.id)
    db.add(assignment)
    db.commit()
    db.refresh(assignment)
    return SightingAssignmentResponse(
        id=assignment.id,
        sighting_id=sighting.id,
        student_id=student.id,
        student_name=student.full_name,
        teacher_id=teacher.id,
        created_at=assignment.created_at,
    )


@router.get("/sessions/{session_id}/sightings", response_model=list[SightingResponse])
def list_sightings(session_id: UUID, teacher: TeacherUser, db: DbSession) -> list[SightingResponse]:
    get_owned_session(session_id, teacher, db)
    rows = db.execute(
        select(Sighting, User)
        .outerjoin(User, User.id == Sighting.student_id)
        .where(Sighting.session_id == session_id)
        .order_by(Sighting.matched_at.desc())
    ).all()
    assignments = {
        assignment.sighting_id: (assignment, student)
        for assignment, student in db.execute(
            select(SightingAssignment, User)
            .join(User, User.id == SightingAssignment.student_id)
            .join(Sighting, Sighting.id == SightingAssignment.sighting_id)
            .where(Sighting.session_id == session_id)
        ).all()
    }
    return [
        SightingResponse(
            id=sighting.id,
            student_id=user.id if user else None,
            student_name=user.full_name if user else "Unknown face",
            camera_source_id=sighting.camera_source_id,
            matched_at=sighting.matched_at,
            face_distance=sighting.face_distance,
            assigned_student_id=assignments[sighting.id][0].student_id if sighting.id in assignments else None,
            assigned_student_name=assignments[sighting.id][1].full_name if sighting.id in assignments else None,
        )
        for sighting, user in rows
    ]
