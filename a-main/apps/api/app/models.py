"""Persistence models for accounts and biometric enrollment."""

from __future__ import annotations

import enum
import uuid
from datetime import datetime

from sqlalchemy import (
    JSON,
    Boolean,
    DateTime,
    Enum,
    ForeignKey,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class UserRole(str, enum.Enum):
    ADMIN = "admin"
    TEACHER = "teacher"
    STUDENT = "student"


class CameraSourceType(str, enum.Enum):
    WEBCAM = "webcam"
    IP_STREAM = "ip_stream"
    VIDEO_FILE = "video_file"


class SessionStatus(str, enum.Enum):
    ACTIVE = "active"
    COMPLETED = "completed"


class AttendanceStatus(str, enum.Enum):
    PRESENT = "present"
    LATE = "late"
    ABSENT = "absent"


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[UserRole] = mapped_column(Enum(UserRole, name="user_role"))
    full_name: Mapped[str] = mapped_column(String(160))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    student_profile: Mapped[StudentProfile | None] = relationship(
        back_populates="user", cascade="all, delete-orphan", uselist=False
    )
    face_encodings: Mapped[list[FaceEncoding]] = relationship(
        back_populates="student", cascade="all, delete-orphan"
    )
    taught_classes: Mapped[list[Classroom]] = relationship(
        back_populates="teacher", cascade="all, delete-orphan"
    )
    class_memberships: Mapped[list[ClassMembership]] = relationship(
        back_populates="student", cascade="all, delete-orphan"
    )
    attendance_override_events: Mapped[list[AttendanceOverrideEvent]] = relationship(
        back_populates="teacher", foreign_keys="AttendanceOverrideEvent.teacher_id"
    )


class StudentProfile(Base):
    __tablename__ = "student_profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    roll_number: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    enrollment_complete: Mapped[bool] = mapped_column(Boolean, default=False)

    user: Mapped[User] = relationship(back_populates="student_profile")


class FaceEncoding(Base):
    __tablename__ = "face_encodings"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    student_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    image_path: Mapped[str] = mapped_column(Text)
    embedding: Mapped[list[float]] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    student: Mapped[User] = relationship(back_populates="face_encodings")


class Classroom(Base):
    __tablename__ = "classes"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    teacher_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(160))
    section: Mapped[str | None] = mapped_column(String(80), nullable=True)
    join_code: Mapped[str] = mapped_column(String(12), unique=True, index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    teacher: Mapped[User] = relationship(back_populates="taught_classes")
    memberships: Mapped[list[ClassMembership]] = relationship(
        back_populates="classroom", cascade="all, delete-orphan"
    )
    camera_sources: Mapped[list[CameraSource]] = relationship(
        back_populates="classroom", cascade="all, delete-orphan"
    )
    sessions: Mapped[list[AttendanceSession]] = relationship(
        back_populates="classroom", cascade="all, delete-orphan"
    )


class ClassMembership(Base):
    __tablename__ = "class_memberships"
    __table_args__ = (UniqueConstraint("class_id", "student_id", name="uq_class_membership"),)

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    class_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("classes.id", ondelete="CASCADE"), index=True)
    student_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    classroom: Mapped[Classroom] = relationship(back_populates="memberships")
    student: Mapped[User] = relationship(back_populates="class_memberships")


class Room(Base):
    __tablename__ = "rooms"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    room_code: Mapped[str] = mapped_column(String(16), unique=True, index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    camera_sources: Mapped[list[CameraSource]] = relationship(back_populates="room")
    sessions: Mapped[list[AttendanceSession]] = relationship(back_populates="room")


class CameraSource(Base):
    __tablename__ = "camera_sources"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    class_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("classes.id", ondelete="CASCADE"), index=True, nullable=True)
    room_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("rooms.id", ondelete="RESTRICT"), index=True, nullable=True)
    label: Mapped[str] = mapped_column(String(100))
    source_type: Mapped[CameraSourceType] = mapped_column(
        Enum(CameraSourceType, name="camera_source_type")
    )
    source: Mapped[str] = mapped_column(Text)
    is_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    classroom: Mapped[Classroom | None] = relationship(back_populates="camera_sources")
    room: Mapped[Room | None] = relationship(back_populates="camera_sources")


class AttendanceSession(Base):
    __tablename__ = "attendance_sessions"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    class_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("classes.id", ondelete="CASCADE"), index=True)
    room_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("rooms.id", ondelete="RESTRICT"), index=True, nullable=True)
    title: Mapped[str] = mapped_column(String(160))
    status: Mapped[SessionStatus] = mapped_column(Enum(SessionStatus, name="session_status"), default=SessionStatus.ACTIVE)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    grace_period_minutes: Mapped[int] = mapped_column(default=10)
    minimum_sightings: Mapped[int] = mapped_column(default=3)
    qualification_window_minutes: Mapped[int] = mapped_column(default=5)

    classroom: Mapped[Classroom] = relationship(back_populates="sessions")
    room: Mapped[Room | None] = relationship(back_populates="sessions")
    sightings: Mapped[list[Sighting]] = relationship(back_populates="session", cascade="all, delete-orphan")
    attendance_records: Mapped[list[AttendanceRecord]] = relationship(
        back_populates="session", cascade="all, delete-orphan"
    )
    override_events: Mapped[list[AttendanceOverrideEvent]] = relationship(
        back_populates="session", cascade="all, delete-orphan"
    )


class Sighting(Base):
    __tablename__ = "sightings"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    session_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("attendance_sessions.id", ondelete="CASCADE"), index=True)
    student_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=True)
    camera_source_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("camera_sources.id", ondelete="CASCADE"))
    matched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    face_distance: Mapped[float | None] = mapped_column(nullable=True)

    session: Mapped[AttendanceSession] = relationship(back_populates="sightings")


class SightingAssignment(Base):
    """Append-only teacher attribution of an anonymous sighting."""

    __tablename__ = "sighting_assignments"
    __table_args__ = (UniqueConstraint("sighting_id", name="uq_sighting_assignment"),)

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    sighting_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("sightings.id", ondelete="CASCADE"), index=True)
    student_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    teacher_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)


class AttendanceRecord(Base):
    __tablename__ = "attendance_records"
    __table_args__ = (UniqueConstraint("session_id", "student_id", name="uq_session_attendance_record"),)

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    session_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("attendance_sessions.id", ondelete="CASCADE"), index=True)
    student_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    automated_status: Mapped[AttendanceStatus] = mapped_column(Enum(AttendanceStatus, name="attendance_status"))
    qualifying_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    session: Mapped[AttendanceSession] = relationship(back_populates="attendance_records")


class AttendanceOverrideEvent(Base):
    """Immutable audit event representing a teacher's manual attendance correction."""

    __tablename__ = "attendance_override_events"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("attendance_sessions.id", ondelete="CASCADE"), index=True
    )
    student_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    teacher_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), index=True
    )
    corrected_status: Mapped[AttendanceStatus] = mapped_column(
        Enum(AttendanceStatus, name="attendance_status"),
    )
    reason: Mapped[str] = mapped_column(String(500))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )

    session: Mapped[AttendanceSession] = relationship(back_populates="override_events")
    teacher: Mapped[User] = relationship(
        back_populates="attendance_override_events", foreign_keys=[teacher_id]
    )
