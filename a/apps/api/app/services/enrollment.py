"""Biometric enrollment validation and local media persistence."""

from __future__ import annotations

import shutil
import uuid

import face_recognition
from app.config import settings
from fastapi import HTTPException, UploadFile, status

ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png"}


def create_face_encodings(student_id: uuid.UUID, photos: list[UploadFile]) -> list[tuple[str, list[float]]]:
    """Save five valid reference photos and derive a face embedding from each."""
    if len(photos) != 5:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Exactly five photos are required.")

    student_directory = settings.media_root / "enrollment" / str(student_id)
    student_directory.mkdir(parents=True, exist_ok=False)
    generated: list[tuple[str, list[float]]] = []

    try:
        for index, photo in enumerate(photos, start=1):
            if photo.content_type not in ALLOWED_CONTENT_TYPES:
                raise HTTPException(
                    status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                    detail="Photos must be JPEG or PNG images.",
                )

            suffix = ".jpg" if photo.content_type == "image/jpeg" else ".png"
            destination = student_directory / f"reference-{index}{suffix}"
            with destination.open("wb") as output:
                shutil.copyfileobj(photo.file, output)

            image = face_recognition.load_image_file(destination)
            encodings = face_recognition.face_encodings(image)
            if len(encodings) != 1:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"Photo {index} must contain exactly one detectable face.",
                )
            generated.append((str(destination.relative_to(settings.media_root)), encodings[0].tolist()))
    except Exception:
        shutil.rmtree(student_directory, ignore_errors=True)
        raise
    finally:
        for photo in photos:
            photo.file.close()

    return generated
