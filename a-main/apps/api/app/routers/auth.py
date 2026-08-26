"""Authentication and role-specific onboarding routes."""

from typing import Annotated
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.models import FaceEncoding, StudentProfile, User, UserRole
from app.schemas import (
    AdminRegistration,
    LoginRequest,
    TeacherRegistration,
    TokenResponse,
    UserResponse,
)
from app.security import (
    CurrentUser,
    create_access_token,
    hash_password,
    verify_password,
)
from app.services.enrollment import create_face_encodings

router = APIRouter(prefix="/auth", tags=["authentication"])
DbSession = Annotated[Session, Depends(get_db)]


def serialize_user(user: User) -> UserResponse:
    profile = user.student_profile
    return UserResponse(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        role=user.role,
        roll_number=profile.roll_number if profile else None,
        enrollment_complete=profile.enrollment_complete if profile else False,
        created_at=user.created_at,
    )


def token_response(user: User) -> TokenResponse:
    return TokenResponse(access_token=create_access_token(user), user=serialize_user(user))


@router.post("/register/teacher", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def register_teacher(payload: TeacherRegistration, db: DbSession) -> TokenResponse:
    if payload.invite_code != settings.teacher_invite_code:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Invalid teacher invite code.")
    user = User(
        email=str(payload.email).lower(),
        password_hash=hash_password(payload.password),
        role=UserRole.TEACHER,
        full_name=payload.full_name.strip(),
    )
    db.add(user)
    try:
        db.commit()
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="An account already uses this email.") from error
    db.refresh(user)
    return token_response(user)


@router.post("/register/admin", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def register_admin(payload: AdminRegistration, db: DbSession) -> TokenResponse:
    if payload.invite_code != settings.admin_invite_code:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Invalid admin invite code.")
    if db.scalar(select(User.id).where(User.role == UserRole.ADMIN)) is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="An admin account already exists.")
    user = User(email=str(payload.email).lower(), password_hash=hash_password(payload.password), role=UserRole.ADMIN, full_name=payload.full_name.strip())
    db.add(user)
    try:
        db.commit()
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="An account already uses this email.") from error
    db.refresh(user)
    return token_response(user)


@router.post("/register/student", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def register_student(
    db: DbSession,
    full_name: Annotated[str, Form(min_length=2, max_length=160)],
    roll_number: Annotated[str, Form(min_length=1, max_length=64)],
    email: Annotated[str, Form()],
    password: Annotated[str, Form(min_length=8, max_length=128)],
    photos: Annotated[list[UploadFile], File()],
) -> TokenResponse:
    normalized_email = email.strip().lower()
    existing = db.scalar(select(User.id).where(User.email == normalized_email))
    if existing is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="An account already uses this email.")
    if db.scalar(select(StudentProfile.user_id).where(StudentProfile.roll_number == roll_number.strip())) is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="A student already uses this roll number.")

    student_id = uuid4()
    encodings = create_face_encodings(student_id, photos)
    user = User(
        id=student_id,
        email=normalized_email,
        password_hash=hash_password(password),
        role=UserRole.STUDENT,
        full_name=full_name.strip(),
        student_profile=StudentProfile(roll_number=roll_number.strip(), enrollment_complete=True),
    )
    user.face_encodings = [FaceEncoding(image_path=path, embedding=embedding) for path, embedding in encodings]
    db.add(user)
    try:
        db.commit()
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Student registration conflicts with existing data.") from error
    db.refresh(user)
    return token_response(user)


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: DbSession) -> TokenResponse:
    identifier = payload.identifier.strip().lower()
    user = db.scalar(
        select(User)
        .outerjoin(StudentProfile, StudentProfile.user_id == User.id)
        .where(or_(User.email == identifier, func.lower(StudentProfile.roll_number) == identifier))
    )
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Incorrect email or password.")
    if not user.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="This account is inactive.")
    return token_response(user)


@router.get("/me", response_model=UserResponse)
def read_current_user(current_user: CurrentUser) -> UserResponse:
    return serialize_user(current_user)
