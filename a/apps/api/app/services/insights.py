"""Explainable, privacy-preserving analytics derived from session sightings."""

from __future__ import annotations

from collections import defaultdict
from datetime import UTC, datetime, timedelta
from uuid import UUID

from app.models import (
    AttendanceOverrideEvent,
    AttendanceRecord,
    AttendanceSession,
    AttendanceStatus,
    CameraSource,
    ClassMembership,
    Sighting,
    SightingAssignment,
    StudentProfile,
    User,
)
from app.services.attendance import (
    LATE_THRESHOLD_PERCENTAGE,
    PRESENT_THRESHOLD_PERCENTAGE,
    observed_window_indexes,
    session_window_count,
)
from app.services.recognition import recognition_manager
from sqlalchemy import select
from sqlalchemy.orm import Session


def build_session_insights(session: AttendanceSession, db: Session) -> dict[str, object]:
    """Build explainable timeline, presence, camera-zone, and review data."""
    now = datetime.now(UTC)
    effective_end = session.ended_at or now
    duration_seconds = max(0, int((effective_end - session.started_at).total_seconds()))
    eligible_windows = session_window_count(session)
    grace_deadline = session.started_at + timedelta(minutes=session.grace_period_minutes)

    member_rows = db.execute(
        select(User, StudentProfile)
        .join(ClassMembership, ClassMembership.student_id == User.id)
        .join(StudentProfile, StudentProfile.user_id == User.id)
        .where(ClassMembership.class_id == session.class_id)
        .order_by(User.full_name)
    ).all()
    sightings = db.scalars(
        select(Sighting).where(Sighting.session_id == session.id).order_by(Sighting.matched_at)
    ).all()
    cameras = db.scalars(
        select(CameraSource)
        .where(
            CameraSource.room_id == session.room_id
            if session.room_id is not None
            else CameraSource.class_id == session.class_id
        )
        .order_by(CameraSource.created_at)
    ).all()
    records = {
        record.student_id: record
        for record in db.scalars(select(AttendanceRecord).where(AttendanceRecord.session_id == session.id)).all()
    }
    latest_overrides: dict[UUID, AttendanceOverrideEvent] = {}
    for event in db.scalars(
        select(AttendanceOverrideEvent)
        .where(AttendanceOverrideEvent.session_id == session.id)
        .order_by(AttendanceOverrideEvent.created_at.desc(), AttendanceOverrideEvent.id.desc())
    ).all():
        latest_overrides.setdefault(event.student_id, event)

    by_student: dict[UUID, list[Sighting]] = defaultdict(list)
    by_camera: dict[UUID, list[Sighting]] = defaultdict(list)
    assignments = {
        item.sighting_id: item.student_id
        for item in db.scalars(
            select(SightingAssignment).join(Sighting, Sighting.id == SightingAssignment.sighting_id).where(Sighting.session_id == session.id)
        ).all()
    }
    for sighting in sightings:
        resolved_student_id = sighting.student_id or assignments.get(sighting.id)
        if resolved_student_id is None:
            continue
        by_student[resolved_student_id].append(sighting)
        by_camera[sighting.camera_source_id].append(sighting)

    students: list[dict[str, object]] = []
    for student, profile in member_rows:
        student_sightings = by_student[student.id]
        observed_windows = len(observed_window_indexes(session, student_sightings))
        percentage = round(observed_windows / eligible_windows * 100, 1)
        first_seen = student_sightings[0].matched_at if student_sightings else None
        last_seen = student_sightings[-1].matched_at if student_sightings else None
        predicted_status = (
            AttendanceStatus.PRESENT
            if percentage >= PRESENT_THRESHOLD_PERCENTAGE and first_seen and first_seen <= grace_deadline
            else AttendanceStatus.LATE
            if percentage >= LATE_THRESHOLD_PERCENTAGE
            else AttendanceStatus.ABSENT
        )
        record = records.get(student.id)
        automated_status = record.automated_status if record else predicted_status
        override = latest_overrides.get(student.id)
        reasons: list[str] = []
        if 25 <= percentage <= 75:
            reasons.append("Borderline presence coverage")
        if first_seen and first_seen > grace_deadline:
            reasons.append("First seen after the grace period")
        if last_seen and duration_seconds >= 600 and last_seen < effective_end - timedelta(minutes=10):
            reasons.append("Not seen near the end of class")
        camera_count = len({item.camera_source_id for item in student_sightings})
        if student_sightings and len(cameras) > 1 and camera_count == 1:
            reasons.append("Seen by only one camera zone")
        if not student_sightings:
            reasons.append("No confident sightings")
        students.append(
            {
                "student_id": student.id,
                "student_name": student.full_name,
                "roll_number": profile.roll_number,
                "automated_status": automated_status,
                "effective_status": override.corrected_status if override else automated_status,
                "observed_windows": observed_windows,
                "eligible_windows": eligible_windows,
                "presence_percentage": percentage,
                "first_seen_at": first_seen,
                "last_seen_at": last_seen,
                "cameras_seen": camera_count,
                "review_reasons": reasons,
            }
        )

    camera_insights: list[dict[str, object]] = []
    for camera in cameras:
        camera_sightings = by_camera[camera.id]
        health = recognition_manager.get_camera_health(session.id, camera.id) if session.ended_at is None else None
        camera_insights.append(
            {
                "camera_source_id": camera.id,
                "label": camera.label,
                "sightings": len(camera_sightings),
                "students_seen": len({item.student_id for item in camera_sightings}),
                "last_frame_at": health.last_frame_at if health else None,
                "status": health.status if health else ("session complete" if camera.is_enabled else "disabled"),
            }
        )

    names = {student.id: student.full_name for student, _profile in member_rows}
    timeline = [
        {
            "student_name": names.get(item.student_id, "Unknown face"),
            "camera_source_id": item.camera_source_id,
            "matched_at": item.matched_at,
        }
        for item in sightings[-200:]
    ]
    return {
        "session_id": session.id,
        "session_title": session.title,
        "duration_seconds": duration_seconds,
        "timeline": timeline,
        "students": students,
        "cameras": camera_insights,
        "review_queue": [student for student in students if student["review_reasons"]],
    }
