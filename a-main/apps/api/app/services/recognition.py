"""Independent InsightFace recognition workers backed by persisted sightings.

Each enabled camera in an active session's room gets its own daemon thread that
reads frames, runs SCRFD detection + ArcFace embedding through the shared
``face_engine``, matches every face against the enrolled gallery with cosine
similarity, and persists confident matches as sightings. A bounded, annotated
JPEG preview is published per worker for the teacher's live camera panel.
"""

from __future__ import annotations

import logging
import threading
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from time import monotonic
from uuid import UUID

import cv2
import numpy as np
from app.config import settings
from app.database import SessionLocal
from app.models import (
    AttendanceSession,
    CameraSource,
    CameraSourceType,
    ClassMembership,
    FaceEncoding,
    SessionStatus,
    Sighting,
    User,
)
from app.services import face_engine
from sqlalchemy import select

logger = logging.getLogger(__name__)

# Cosine-similarity threshold for a confident identity match. Sourced from
# settings so it can be tuned per deployment without a code change.
MATCH_SIMILARITY = settings.face_match_similarity
SAMPLE_INTERVAL_SECONDS = settings.recognition_sample_interval_seconds
PREVIEW_INTERVAL_SECONDS = 0.1
PREVIEW_WIDTH = 640
UNKNOWN_EVENT_INTERVAL = timedelta(seconds=5)
DEDUPLICATION_WINDOW = timedelta(seconds=5)


@dataclass
class WorkerHandle:
    camera_id: UUID
    stop_event: threading.Event
    thread: threading.Thread


@dataclass
class CameraHealth:
    last_frame_at: datetime | None = None
    last_attempt_at: datetime | None = None
    status: str = "starting"


def parse_capture_source(source_type: CameraSourceType, source: str) -> int | str:
    return int(source) if source_type is CameraSourceType.WEBCAM and source.isdigit() else source


def _downscale_for_processing(frame: np.ndarray) -> np.ndarray:
    """Cap the frame width so processing/preview stay bounded on large CCTV feeds.

    The result is deterministic for a fixed input size, so detection boxes
    computed on this frame stay valid when drawn on a later preview frame from
    the same camera. Detection sensitivity to small faces is governed by
    ``face_det_size``, not by this cap.
    """
    max_width = settings.face_max_frame_width
    height, width = frame.shape[:2]
    if width <= max_width:
        return frame
    scale = max_width / width
    return cv2.resize(frame, (max_width, int(round(height * scale))), interpolation=cv2.INTER_AREA)


def log_sighting(session_id: UUID, student_id: UUID, camera_id: UUID, distance: float) -> None:
    """Persist a match unless another camera already logged it in the five-second merge window."""
    matched_at = datetime.now(UTC)
    with SessionLocal() as db:
        session = db.get(AttendanceSession, session_id)
        if session is None or session.status is not SessionStatus.ACTIVE:
            return
        duplicate = db.scalar(
            select(Sighting.id)
            .where(
                Sighting.session_id == session_id,
                Sighting.student_id == student_id,
                Sighting.camera_source_id != camera_id,
                Sighting.matched_at >= matched_at - DEDUPLICATION_WINDOW,
            )
            .limit(1)
        )
        if duplicate is None:
            db.add(
                Sighting(
                    session_id=session_id,
                    student_id=student_id,
                    camera_source_id=camera_id,
                    matched_at=matched_at,
                    face_distance=distance,
                )
            )
            db.commit()


def log_unknown_sighting(session_id: UUID, camera_id: UUID) -> None:
    """Persist at most one anonymous event per camera every five seconds."""
    matched_at = datetime.now(UTC)
    with SessionLocal() as db:
        session = db.get(AttendanceSession, session_id)
        if session is None or session.status is not SessionStatus.ACTIVE:
            return
        recent_unknown = db.scalar(
            select(Sighting.id)
            .where(
                Sighting.session_id == session_id,
                Sighting.student_id.is_(None),
                Sighting.camera_source_id == camera_id,
                Sighting.matched_at >= matched_at - UNKNOWN_EVENT_INTERVAL,
            )
            .limit(1)
        )
        if recent_unknown is None:
            db.add(
                Sighting(
                    session_id=session_id,
                    student_id=None,
                    camera_source_id=camera_id,
                    matched_at=matched_at,
                    face_distance=None,
                )
            )
            db.commit()


def run_worker(
    session_id: UUID,
    camera: CameraSource,
    known_student_ids: list[UUID],
    known_student_names: list[str],
    known_embeddings: list[list[float]],
    stop_event: threading.Event,
) -> None:
    """Read one camera source and independently log confident student matches."""
    capture = cv2.VideoCapture(parse_capture_source(camera.source_type, camera.source))
    capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    # Normalized gallery matrix (N, 512) for one-shot cosine scoring; empty when
    # no enrolled student has a model-compatible embedding.
    known_vectors = np.asarray(known_embeddings, dtype=np.float32)
    last_processed_at = 0.0
    last_preview_at = 0.0
    # Each annotation is (left, top, right, bottom, label, color) in the
    # coordinate space of the downscaled processing frame.
    annotations: list[tuple[int, int, int, int, str, tuple[int, int, int]]] = []
    try:
        while not stop_event.is_set():
            read_ok, frame = capture.read()
            if not read_ok:
                recognition_manager.mark_camera_attempt(session_id, camera.id, successful=False)
                if camera.source_type is CameraSourceType.VIDEO_FILE:
                    break
                stop_event.wait(0.1)
                continue

            recognition_manager.mark_camera_attempt(session_id, camera.id, successful=True)
            now = monotonic()
            process_tick = now - last_processed_at >= SAMPLE_INTERVAL_SECONDS
            preview_tick = now - last_preview_at >= PREVIEW_INTERVAL_SECONDS
            if not (process_tick or preview_tick):
                continue

            processing_frame = _downscale_for_processing(frame)

            if process_tick:
                last_processed_at = now
                annotations = []
                for face in face_engine.detect_faces(processing_frame):
                    left, top, right, bottom = face.bbox
                    label = "Unknown"
                    color = (80, 80, 220)
                    matched = False
                    similarities = face_engine.cosine_similarity_matrix(known_vectors, face.embedding)
                    if similarities.size:
                        best_index = int(np.argmax(similarities))
                        similarity = float(similarities[best_index])
                        if similarity >= MATCH_SIMILARITY:
                            matched = True
                            label = known_student_names[best_index]
                            color = (70, 180, 90)
                            log_sighting(
                                session_id,
                                known_student_ids[best_index],
                                camera.id,
                                round(1.0 - similarity, 4),
                            )
                    if not matched:
                        log_unknown_sighting(session_id, camera.id)
                    annotations.append((left, top, right, bottom, label, color))

            if preview_tick:
                last_preview_at = now
                for left, top, right, bottom, label, color in annotations:
                    cv2.rectangle(processing_frame, (left, top), (right, bottom), color, 2)
                    cv2.rectangle(
                        processing_frame, (left, max(0, bottom - 30)), (right, bottom), color, cv2.FILLED
                    )
                    cv2.putText(
                        processing_frame,
                        label,
                        (left + 6, bottom - 9),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.55,
                        (255, 255, 255),
                        1,
                        cv2.LINE_AA,
                    )
                preview = processing_frame
                if processing_frame.shape[1] > PREVIEW_WIDTH:
                    preview = cv2.resize(
                        processing_frame,
                        (PREVIEW_WIDTH, int(processing_frame.shape[0] * PREVIEW_WIDTH / processing_frame.shape[1])),
                    )
                recognition_manager.publish_frame(session_id, camera.id, preview)
    finally:
        capture.release()


class RecognitionManager:
    """Owns process-local worker threads for active attendance sessions."""

    def __init__(self) -> None:
        self._workers: dict[UUID, list[WorkerHandle]] = {}
        self._preview_frames: dict[tuple[UUID, UUID], bytes] = {}
        self._camera_health: dict[tuple[UUID, UUID], CameraHealth] = {}
        self._lock = threading.Lock()

    def mark_camera_attempt(self, session_id: UUID, camera_id: UUID, successful: bool) -> None:
        with self._lock:
            health = self._camera_health.setdefault((session_id, camera_id), CameraHealth())
            now = datetime.now(UTC)
            health.last_attempt_at = now
            if successful:
                health.last_frame_at = now
                health.status = "healthy"
            elif health.last_frame_at is None or (now - health.last_frame_at).total_seconds() > 5:
                health.status = "offline"

    def get_camera_health(self, session_id: UUID, camera_id: UUID) -> CameraHealth:
        with self._lock:
            health = self._camera_health.get((session_id, camera_id))
            if health is None:
                return CameraHealth(status="offline")
            if health.last_frame_at and (datetime.now(UTC) - health.last_frame_at).total_seconds() > 5:
                health.status = "degraded"
            return CameraHealth(health.last_frame_at, health.last_attempt_at, health.status)

    def publish_frame(self, session_id: UUID, camera_id: UUID, frame: np.ndarray) -> None:
        """Keep one bounded JPEG preview per worker without retaining raw frame history."""
        encoded, buffer = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 78])
        if encoded:
            with self._lock:
                self._preview_frames[(session_id, camera_id)] = buffer.tobytes()

    def get_preview_frame(self, session_id: UUID, camera_id: UUID) -> bytes | None:
        with self._lock:
            return self._preview_frames.get((session_id, camera_id))

    def start_session(self, session_id: UUID) -> int:
        with self._lock, SessionLocal() as db:
            session = db.get(AttendanceSession, session_id)
            if session is None:
                return 0
            sources = db.scalars(
                select(CameraSource).where(
                    CameraSource.room_id == session.room_id,
                    CameraSource.is_enabled.is_(True),
                )
            ).all()
            enrolled = db.execute(
                select(FaceEncoding.student_id, User.full_name, FaceEncoding.embedding)
                .join(User, User.id == FaceEncoding.student_id)
                .join(ClassMembership, ClassMembership.student_id == FaceEncoding.student_id)
                .where(ClassMembership.class_id == session.class_id)
            ).all()
            # Only load embeddings that match the current model's width. This
            # keeps a database that still holds legacy 128-d dlib encodings from
            # crashing the cosine matcher; those students simply need to
            # re-enroll to be recognized by the InsightFace pipeline.
            expected_dim = face_engine.expected_dim()
            student_ids: list[UUID] = []
            student_names: list[str] = []
            embeddings: list[list[float]] = []
            skipped = 0
            for student_id, name, embedding in enrolled:
                if embedding is None or len(embedding) != expected_dim:
                    skipped += 1
                    continue
                student_ids.append(student_id)
                student_names.append(name)
                embeddings.append(embedding)
            if skipped:
                logger.warning(
                    "Session %s: skipped %d enrolled embedding(s) incompatible with the "
                    "current model (expected %d-d). Affected students must re-enroll.",
                    session_id,
                    skipped,
                    expected_dim,
                )
            handles: list[WorkerHandle] = []
            for camera in sources:
                stop_event = threading.Event()
                thread = threading.Thread(
                    target=run_worker,
                    args=(session_id, camera, student_ids, student_names, embeddings, stop_event),
                    daemon=True,
                    name=f"recognition-{session_id}-{camera.id}",
                )
                thread.start()
                handles.append(WorkerHandle(camera_id=camera.id, stop_event=stop_event, thread=thread))
            self._workers[session_id] = handles
            for camera in sources:
                self._camera_health[(session_id, camera.id)] = CameraHealth()
            return len(handles)

    def stop_session(self, session_id: UUID) -> None:
        with self._lock:
            handles = self._workers.pop(session_id, [])
        for handle in handles:
            handle.stop_event.set()
        for handle in handles:
            handle.thread.join(timeout=3)
        with self._lock:
            for handle in handles:
                self._preview_frames.pop((session_id, handle.camera_id), None)
                self._camera_health.pop((session_id, handle.camera_id), None)

    def stop_all(self) -> None:
        for session_id in list(self._workers):
            self.stop_session(session_id)


recognition_manager = RecognitionManager()
