"""Biometric enrollment validation and local media persistence.

Enrollment derives one 512-d ArcFace embedding per reference photo using the
shared InsightFace engine (SCRFD detection + landmark alignment + ArcFace), so
the enrolled gallery lives in the exact same vector space as the live camera
probes produced by the recognition workers.
"""

from __future__ import annotations

import shutil
import uuid

import cv2
import numpy as np
from app.config import settings
from app.services import face_engine
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

            image = cv2.imread(str(destination), cv2.IMREAD_COLOR)  # BGR, as InsightFace expects.
            if image is None:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"Photo {index} could not be read as an image.",
                )

            faces = face_engine.detect_faces(image)
            if len(faces) != 1:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"Photo {index} must contain exactly one detectable face.",
                )
            embedding = np.asarray(faces[0].embedding, dtype=np.float32)
            generated.append((str(destination.relative_to(settings.media_root)), embedding.tolist()))
    except Exception:
        shutil.rmtree(student_directory, ignore_errors=True)
        raise
    finally:
        for photo in photos:
            photo.file.close()

    return generated
