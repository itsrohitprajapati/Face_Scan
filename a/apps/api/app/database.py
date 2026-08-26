"""SQLAlchemy database setup."""

from collections.abc import Generator

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import settings


class Base(DeclarativeBase):
    """Base class for all database models."""


engine = create_engine(settings.database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


def ensure_anonymous_sightings_compatible() -> None:
    """Keep existing local databases compatible with anonymous recognition events."""
    if engine.dialect.name != "postgresql":
        return
    columns = {column["name"]: column for column in inspect(engine).get_columns("sightings")}
    nullable_columns = [
        name for name in ("student_id", "face_distance") if columns.get(name, {}).get("nullable") is False
    ]
    if nullable_columns:
        with engine.begin() as connection:
            for column_name in nullable_columns:
                connection.execute(text(f"ALTER TABLE sightings ALTER COLUMN {column_name} DROP NOT NULL"))


def ensure_room_schema_compatible() -> None:
    """Add nullable room links to existing local databases without destructive migration."""
    if engine.dialect.name != "postgresql":
        return
    table_names = set(inspect(engine).get_table_names())
    with engine.begin() as connection:
        if "users" in table_names:
            enum_values = connection.execute(text("SELECT enumlabel FROM pg_enum WHERE enumtypid = 'user_role'::regtype")).scalars().all()
            # SQLAlchemy's default Enum mapping persists Python enum names
            # (TEACHER/STUDENT/ADMIN), not their lowercase values. Older
            # development databases may contain the incorrectly-added
            # lowercase `admin` label, so normalize it in place.
            if "admin" in enum_values and "ADMIN" not in enum_values:
                connection.execute(text("ALTER TYPE user_role RENAME VALUE 'admin' TO 'ADMIN'"))
            elif "ADMIN" not in enum_values:
                connection.execute(text("ALTER TYPE user_role ADD VALUE 'ADMIN'"))
        if "camera_sources" in table_names:
            camera_columns = {column["name"]: column for column in inspect(engine).get_columns("camera_sources")}
            if camera_columns.get("class_id", {}).get("nullable") is False:
                connection.execute(text("ALTER TABLE camera_sources ALTER COLUMN class_id DROP NOT NULL"))
            if "room_id" not in camera_columns:
                connection.execute(text("ALTER TABLE camera_sources ADD COLUMN room_id UUID REFERENCES rooms(id) ON DELETE RESTRICT"))
                connection.execute(text("CREATE INDEX ix_camera_sources_room_id ON camera_sources (room_id)"))
        if "attendance_sessions" in table_names:
            columns = {column["name"] for column in inspect(engine).get_columns("attendance_sessions")}
            if "room_id" not in columns:
                connection.execute(text("ALTER TABLE attendance_sessions ADD COLUMN room_id UUID REFERENCES rooms(id) ON DELETE RESTRICT"))
                connection.execute(text("CREATE INDEX ix_attendance_sessions_room_id ON attendance_sessions (room_id)"))


def get_db() -> Generator[Session, None, None]:
    """Provide one transaction-scoped database session per request."""
    database = SessionLocal()
    try:
        yield database
    finally:
        database.close()
