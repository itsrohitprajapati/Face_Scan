"""Request and response schemas exposed by the API."""

from datetime import datetime
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, StringConstraints

from app.models import AttendanceStatus, CameraSourceType, SessionStatus, UserRole


class TeacherRegistration(BaseModel):
    full_name: str = Field(min_length=2, max_length=160)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    invite_code: str = Field(min_length=1, max_length=128)


class AdminRegistration(TeacherRegistration):
    pass


class LoginRequest(BaseModel):
    identifier: str = Field(min_length=1, max_length=320)
    password: str = Field(min_length=8, max_length=128)


class UserResponse(BaseModel):
    id: UUID
    email: EmailStr
    full_name: str
    role: UserRole
    roll_number: str | None = None
    enrollment_complete: bool = False
    created_at: datetime


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse


class RoomCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)


class RoomUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    is_active: bool | None = None


class RoomResponse(BaseModel):
    id: UUID
    name: str
    room_code: str
    is_active: bool
    camera_count: int = 0
    enabled_camera_count: int = 0
    active_session_id: UUID | None = None
    active_session_title: str | None = None
    created_at: datetime


class RoomCameraCreate(BaseModel):
    label: str = Field(min_length=2, max_length=100)
    source_type: CameraSourceType
    source: str = Field(min_length=1, max_length=2048)


class RoomCameraUpdate(BaseModel):
    label: str | None = Field(default=None, min_length=2, max_length=100)
    source_type: CameraSourceType | None = None
    source: str | None = Field(default=None, min_length=1, max_length=2048)
    is_enabled: bool | None = None


class ClassroomCreate(BaseModel):
    name: str = Field(min_length=2, max_length=160)
    section: str | None = Field(default=None, max_length=80)


class ClassroomResponse(BaseModel):
    id: UUID
    name: str
    section: str | None
    join_code: str
    teacher_name: str
    created_at: datetime


class JoinClassRequest(BaseModel):
    join_code: str = Field(min_length=4, max_length=12)


class ClassStudentResponse(BaseModel):
    id: UUID
    full_name: str
    email: EmailStr
    roll_number: str
    joined_at: datetime


class ActiveTeacherSessionResponse(BaseModel):
    class_id: UUID | None = None
    class_name: str | None = None
    session_id: UUID | None = None


class CameraSourceCreate(BaseModel):
    label: str = Field(min_length=2, max_length=100)
    source_type: CameraSourceType
    source: str = Field(min_length=1, max_length=2048)


class CameraSourceUpdate(BaseModel):
    label: str | None = Field(default=None, min_length=2, max_length=100)
    source_type: CameraSourceType | None = None
    source: str | None = Field(default=None, min_length=1, max_length=2048)
    is_enabled: bool | None = None


class CameraSourceResponse(BaseModel):
    id: UUID
    label: str
    source_type: CameraSourceType
    source: str
    is_enabled: bool
    created_at: datetime
    updated_at: datetime


class AttendanceSessionCreate(BaseModel):
    title: str = Field(min_length=2, max_length=160)
    room_code: str = Field(min_length=1, max_length=16)
    grace_period_minutes: int = Field(default=10, ge=0, le=120)
    minimum_sightings: int = Field(default=1, ge=1, le=20)
    qualification_window_minutes: int = Field(default=1, ge=1, le=60)


class AttendanceSessionResponse(BaseModel):
    id: UUID
    class_id: UUID
    room_id: UUID | None
    room_name: str | None
    room_code: str | None
    title: str
    status: SessionStatus
    started_at: datetime
    ended_at: datetime | None
    grace_period_minutes: int
    minimum_sightings: int
    qualification_window_minutes: int
    presence_threshold_percentage: float = 70.0


class AttendanceOverrideCreate(BaseModel):
    status: AttendanceStatus
    reason: Annotated[str, StringConstraints(strip_whitespace=True, max_length=500)] = "Teacher correction"


class AttendanceOverrideResponse(BaseModel):
    id: UUID
    status: AttendanceStatus
    reason: str
    teacher_id: UUID
    teacher_name: str
    created_at: datetime


class AttendanceRecordResponse(BaseModel):
    student_id: UUID
    student_name: str
    roll_number: str
    automated_status: AttendanceStatus
    effective_status: AttendanceStatus
    qualifying_at: datetime | None
    observed_windows: int = 0
    eligible_windows: int = 0
    presence_percentage: float = 0.0
    latest_override: AttendanceOverrideResponse | None = None
    override_history: list[AttendanceOverrideResponse] = Field(default_factory=list)


class StudentAttendanceEntry(BaseModel):
    session_id: UUID
    class_id: UUID
    class_name: str
    session_title: str
    session_started_at: datetime
    session_ended_at: datetime | None
    automated_status: AttendanceStatus
    effective_status: AttendanceStatus
    qualifying_at: datetime | None
    observed_windows: int
    eligible_windows: int
    presence_percentage: float


class StudentAttendanceSummary(BaseModel):
    total_sessions: int
    attended_sessions: int
    present_sessions: int
    late_sessions: int
    absent_sessions: int
    attendance_percentage: float
    history: list[StudentAttendanceEntry]


class SightingResponse(BaseModel):
    id: UUID
    student_id: UUID | None
    student_name: str
    camera_source_id: UUID
    matched_at: datetime
    face_distance: float | None
    assigned_student_id: UUID | None = None
    assigned_student_name: str | None = None


class SightingAssignmentResponse(BaseModel):
    id: UUID
    sighting_id: UUID
    student_id: UUID
    student_name: str
    teacher_id: UUID
    created_at: datetime


class StudentInsightResponse(BaseModel):
    student_id: UUID
    student_name: str
    roll_number: str
    automated_status: AttendanceStatus
    effective_status: AttendanceStatus
    observed_windows: int
    eligible_windows: int
    presence_percentage: float
    first_seen_at: datetime | None
    last_seen_at: datetime | None
    cameras_seen: int
    review_reasons: list[str] = Field(default_factory=list)


class TimelineEventResponse(BaseModel):
    student_name: str
    camera_source_id: UUID
    matched_at: datetime


class CameraInsightResponse(BaseModel):
    camera_source_id: UUID
    label: str
    sightings: int
    students_seen: int
    last_frame_at: datetime | None = None
    status: str = "unknown"


class SessionInsightsResponse(BaseModel):
    session_id: UUID
    session_title: str
    duration_seconds: int
    timeline: list[TimelineEventResponse]
    students: list[StudentInsightResponse]
    cameras: list[CameraInsightResponse]
    review_queue: list[StudentInsightResponse]


class AttendanceQueryRequest(BaseModel):
    query: str = Field(min_length=2, max_length=500)
    class_id: UUID | None = None


class AttendanceQueryInterpretation(BaseModel):
    summary: str
    start_date: str | None = None
    end_date: str | None = None
    status: AttendanceStatus | None = None
    student_name: str | None = None
    class_name: str | None = None


class AttendanceQueryRow(BaseModel):
    session_id: UUID
    class_id: UUID
    class_name: str
    session_title: str
    session_started_at: datetime
    session_ended_at: datetime | None
    student_id: UUID
    student_name: str
    roll_number: str
    automated_status: AttendanceStatus
    effective_status: AttendanceStatus
    observed_windows: int
    eligible_windows: int
    presence_percentage: float


class AttendanceQueryResponse(BaseModel):
    interpretation: AttendanceQueryInterpretation
    total_matches: int
    present_count: int
    late_count: int
    absent_count: int
    average_presence_percentage: float
    rows: list[AttendanceQueryRow]


class AttendanceAssistantResponse(BaseModel):
    answer: str
    data: AttendanceQueryResponse | None = None
