"""Safe, explainable natural-language queries over teacher-owned attendance history."""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from uuid import UUID

from app.models import (
    AttendanceOverrideEvent,
    AttendanceRecord,
    AttendanceSession,
    AttendanceStatus,
    Classroom,
    SessionStatus,
    Sighting,
    SightingAssignment,
    StudentProfile,
    User,
)
from app.services.attendance import coverage_for_record
from sqlalchemy import select
from sqlalchemy.orm import Session

MAX_RESULT_ROWS = 200
_DATE_TOKEN = re.compile(r"\b(?:\d{4}-\d{1,2}-\d{1,2}|\d{1,2}[/-]\d{1,2}[/-]\d{4})\b")


@dataclass(frozen=True)
class QueryFilters:
    start_date: date | None
    end_date: date | None
    status: AttendanceStatus | None


def _parse_date(value: str) -> date | None:
    for pattern in ("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y"):
        try:
            return datetime.strptime(value, pattern).replace(tzinfo=UTC).date()
        except ValueError:
            continue
    return None


def parse_query(query: str, today: date | None = None) -> QueryFilters:
    """Map supported date and status language to explicit, inspectable filters."""
    normalized = " ".join(query.lower().split())
    current = today or datetime.now(UTC).date()
    start_date: date | None = None
    end_date: date | None = None

    if "yesterday" in normalized:
        start_date = end_date = current - timedelta(days=1)
    elif "today" in normalized:
        start_date = end_date = current
    elif "last week" in normalized:
        this_week = current - timedelta(days=current.weekday())
        start_date, end_date = this_week - timedelta(days=7), this_week - timedelta(days=1)
    elif "this week" in normalized:
        start_date, end_date = current - timedelta(days=current.weekday()), current
    elif "last month" in normalized:
        first_this_month = current.replace(day=1)
        end_date = first_this_month - timedelta(days=1)
        start_date = end_date.replace(day=1)
    elif "this month" in normalized:
        start_date, end_date = current.replace(day=1), current
    else:
        parsed_dates = [parsed for token in _DATE_TOKEN.findall(normalized) if (parsed := _parse_date(token))]
        if len(parsed_dates) >= 2:
            start_date, end_date = min(parsed_dates[0], parsed_dates[1]), max(parsed_dates[0], parsed_dates[1])
        elif parsed_dates:
            start_date = end_date = parsed_dates[0]

    status_filter = None
    for attendance_status in AttendanceStatus:
        if re.search(rf"\b{attendance_status.value}\b", normalized):
            status_filter = attendance_status
            break
    return QueryFilters(start_date=start_date, end_date=end_date, status=status_filter)


def _filter_summary(
    filters: QueryFilters,
    class_name: str | None,
    student_name: str | None,
) -> str:
    parts = [f"class {class_name}" if class_name else "all your classes"]
    if filters.start_date and filters.end_date:
        if filters.start_date == filters.end_date:
            parts.append(f"on {filters.start_date.isoformat()}")
        else:
            parts.append(f"from {filters.start_date.isoformat()} to {filters.end_date.isoformat()}")
    else:
        parts.append("across all completed sessions")
    if student_name:
        parts.append(f"for {student_name}")
    if filters.status:
        parts.append(f"with effective status {filters.status.value.title()}")
    return "Attendance in " + ", ".join(parts) + "."


def query_attendance(
    query: str,
    teacher_id: UUID,
    db: Session,
    class_id: UUID | None = None,
) -> dict[str, object]:
    """Return bounded attendance rows; natural language never becomes SQL."""
    filters = parse_query(query)
    statement = (
        select(AttendanceRecord, AttendanceSession, Classroom, User, StudentProfile)
        .join(AttendanceSession, AttendanceSession.id == AttendanceRecord.session_id)
        .join(Classroom, Classroom.id == AttendanceSession.class_id)
        .join(User, User.id == AttendanceRecord.student_id)
        .join(StudentProfile, StudentProfile.user_id == User.id)
        .where(
            Classroom.teacher_id == teacher_id,
            AttendanceSession.status == SessionStatus.COMPLETED,
        )
        .order_by(AttendanceSession.started_at.desc(), User.full_name)
    )
    if class_id is not None:
        statement = statement.where(Classroom.id == class_id)
    candidate_rows = db.execute(statement).all()

    normalized_query = " ".join(query.casefold().split())
    matching_students = {
        student.id: student.full_name
        for _record, _session, _classroom, student, profile in candidate_rows
        if student.full_name.casefold() in normalized_query
        or profile.roll_number.casefold() in normalized_query
    }
    student_name = next(iter(matching_students.values()), None) if len(matching_students) == 1 else None
    matching_student_ids = set(matching_students) if matching_students else None

    dated_rows = []
    for row in candidate_rows:
        _record, session, _classroom, student, _profile = row
        session_date = session.started_at.date()
        if filters.start_date and session_date < filters.start_date:
            continue
        if filters.end_date and session_date > filters.end_date:
            continue
        if matching_student_ids is not None and student.id not in matching_student_ids:
            continue
        dated_rows.append(row)

    session_ids = {session.id for _record, session, _classroom, _student, _profile in dated_rows}
    sightings = db.scalars(select(Sighting).where(Sighting.session_id.in_(session_ids))).all() if session_ids else []
    assignments = {
        assignment.sighting_id: assignment.student_id
        for assignment in db.scalars(
            select(SightingAssignment)
            .join(Sighting, Sighting.id == SightingAssignment.sighting_id)
            .where(Sighting.session_id.in_(session_ids))
        ).all()
    } if session_ids else {}
    sightings_by_record: dict[tuple[UUID, UUID], list[Sighting]] = {}
    for sighting in sightings:
        resolved_student_id = sighting.student_id or assignments.get(sighting.id)
        if resolved_student_id:
            sightings_by_record.setdefault((sighting.session_id, resolved_student_id), []).append(sighting)

    latest_overrides: dict[tuple[UUID, UUID], AttendanceOverrideEvent] = {}
    if session_ids:
        override_events = db.scalars(
            select(AttendanceOverrideEvent)
            .where(AttendanceOverrideEvent.session_id.in_(session_ids))
            .order_by(AttendanceOverrideEvent.created_at.desc(), AttendanceOverrideEvent.id.desc())
        ).all()
        for event in override_events:
            latest_overrides.setdefault((event.session_id, event.student_id), event)

    result_rows: list[dict[str, object]] = []
    for record, session, classroom, student, profile in dated_rows:
        override = latest_overrides.get((session.id, student.id))
        effective_status = override.corrected_status if override else record.automated_status
        if filters.status and effective_status is not filters.status:
            continue
        observed, eligible, percentage = coverage_for_record(
            session, sightings_by_record.get((session.id, student.id), [])
        )
        result_rows.append(
            {
                "session_id": session.id,
                "class_id": classroom.id,
                "class_name": classroom.name,
                "session_title": session.title,
                "session_started_at": session.started_at,
                "session_ended_at": session.ended_at,
                "student_id": student.id,
                "student_name": student.full_name,
                "roll_number": profile.roll_number,
                "automated_status": record.automated_status,
                "effective_status": effective_status,
                "observed_windows": observed,
                "eligible_windows": eligible,
                "presence_percentage": percentage,
            }
        )

    class_names = {classroom.name for _record, _session, classroom, _student, _profile in candidate_rows}
    selected_class_name = next(iter(class_names), None) if class_id and len(class_names) == 1 else None
    statuses = [row["effective_status"] for row in result_rows]
    percentages = [float(row["presence_percentage"]) for row in result_rows]
    return {
        "interpretation": {
            "summary": _filter_summary(filters, selected_class_name, student_name),
            "start_date": filters.start_date.isoformat() if filters.start_date else None,
            "end_date": filters.end_date.isoformat() if filters.end_date else None,
            "status": filters.status,
            "student_name": student_name,
            "class_name": selected_class_name,
        },
        "total_matches": len(result_rows),
        "present_count": statuses.count(AttendanceStatus.PRESENT),
        "late_count": statuses.count(AttendanceStatus.LATE),
        "absent_count": statuses.count(AttendanceStatus.ABSENT),
        "average_presence_percentage": round(sum(percentages) / len(percentages), 1) if percentages else 0.0,
        "rows": result_rows[:MAX_RESULT_ROWS],
    }
