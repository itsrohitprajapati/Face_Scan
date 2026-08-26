"""Shared InsightFace engine: SCRFD detection + landmark alignment + ArcFace embeddings.

A single process-wide model is loaded lazily and guarded by a lock so the
per-camera recognition threads and the enrollment request handler can all
share one detector/recognizer instance. ONNX Runtime's ``InferenceSession.run``
is thread-safe, so the model is *not* locked during inference — only during the
one-time load — which lets multiple camera workers detect concurrently.

Why InsightFace over the previous dlib/``face_recognition`` stack:

* **SCRFD** detects small, tilted, and partially-occluded faces far better than
  dlib's HOG detector — exactly the hard cases in wide-angle CCTV classroom
  footage.
* Detection is followed by **5-point landmark alignment** before the recognizer
  runs, which is what lets **ArcFace** reach its accuracy.
* Embeddings are 512-d and compared with **cosine similarity**.

Enrollment and recognition both go through this module, so the enrollment
gallery and the live probes always live in the same vector space.
"""

from __future__ import annotations

import threading
from dataclasses import dataclass

import numpy as np

from app.config import settings

# ArcFace recognizer output width for the bundled model packs
# (``buffalo_l`` -> w600k_r50, ``buffalo_s`` -> w600k_mbf). Both emit 512-d.
EMBEDDING_DIM = 512

_engine_lock = threading.Lock()
_app = None  # insightface.app.FaceAnalysis, loaded lazily on first use.


@dataclass
class DetectedFace:
    """One detected face expressed in the coordinate space of the frame passed in."""

    # (left, top, right, bottom), integer pixel coordinates clamped to the frame.
    bbox: tuple[int, int, int, int]
    det_score: float
    # L2-normalized ArcFace embedding, float32, length == EMBEDDING_DIM.
    embedding: np.ndarray


def expected_dim() -> int:
    """Embedding width this engine emits — used to reject stale/foreign vectors."""
    return EMBEDDING_DIM


def _load_app():
    """Build (once) and return the shared InsightFace ``FaceAnalysis`` app."""
    global _app
    if _app is not None:
        return _app
    with _engine_lock:
        if _app is not None:
            return _app
        # Imported lazily so importing this module (tooling, `compileall`, the
        # FastAPI app object) does not require the native ONNX Runtime stack.
        from insightface.app import FaceAnalysis

        providers = (
            ["CUDAExecutionProvider", "CPUExecutionProvider"]
            if settings.face_use_gpu
            else ["CPUExecutionProvider"]
        )
        app = FaceAnalysis(name=settings.face_model_pack, providers=providers, allowed_modules=["detection", "recognition"])
        det = settings.face_det_size
        app.prepare(
            ctx_id=settings.face_ctx_id if settings.face_use_gpu else -1,
            det_size=(det, det),
            det_thresh=settings.face_det_threshold,
        )
        _app = app
        return _app


def warmup() -> None:
    """Force the model to load now (used by setup/verification scripts)."""
    _load_app()


def _normalize(vector: np.ndarray) -> np.ndarray:
    norm = float(np.linalg.norm(vector))
    return vector / norm if norm > 0 else vector


def _embedding_of(face) -> np.ndarray:
    """Return the L2-normalized embedding of an InsightFace ``Face`` object."""
    normed = getattr(face, "normed_embedding", None)
    if normed is not None:
        return np.asarray(normed, dtype=np.float32)
    return _normalize(np.asarray(face.embedding, dtype=np.float32))


def detect_faces(bgr_image: np.ndarray) -> list[DetectedFace]:
    """Detect every face in a BGR frame and return aligned, normalized embeddings.

    InsightFace expects OpenCV's native **BGR** layout (it swaps channels
    internally), so — unlike the old ``face_recognition`` path — callers must
    *not* convert to RGB first.
    """
    app = _load_app()
    height, width = bgr_image.shape[:2]
    results: list[DetectedFace] = []
    for face in app.get(bgr_image):
        x1, y1, x2, y2 = (int(round(value)) for value in face.bbox)
        left = max(0, min(x1, width - 1))
        top = max(0, min(y1, height - 1))
        right = max(left + 1, min(x2, width))
        bottom = max(top + 1, min(y2, height))
        results.append(
            DetectedFace(
                bbox=(left, top, right, bottom),
                det_score=float(getattr(face, "det_score", 0.0)),
                embedding=_embedding_of(face),
            )
        )
    return results


def embed_largest_face(bgr_image: np.ndarray) -> DetectedFace | None:
    """Return the highest-confidence face in the frame, or ``None`` if there are none."""
    faces = detect_faces(bgr_image)
    if not faces:
        return None
    return max(faces, key=lambda face: face.det_score)


def cosine_similarity_matrix(gallery: np.ndarray, probe: np.ndarray) -> np.ndarray:
    """Cosine similarity of one normalized probe against a normalized gallery matrix.

    Both inputs are assumed L2-normalized (they are, coming out of this engine),
    so the cosine similarity is a plain dot product. Returns a 1-D array aligned
    with the gallery rows; empty gallery yields an empty array.
    """
    if gallery.size == 0:
        return np.empty((0,), dtype=np.float32)
    return gallery @ probe
