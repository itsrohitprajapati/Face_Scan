"""Verify the InsightFace stack and a configured OpenCV camera source."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import cv2

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

import insightface  # noqa: E402
import onnxruntime  # noqa: E402

from app.config import settings  # noqa: E402
from app.services import face_engine  # noqa: E402


def parse_source(value: str) -> int | str:
    """Treat numeric sources as local camera indexes and all other values as URLs/files."""
    return int(value) if value.isdigit() else value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        default="0",
        help="Camera index, IP-stream URL, or video-file path (default: 0).",
    )
    arguments = parser.parse_args()

    print(f"insightface={insightface.__version__}")
    print(f"onnxruntime={onnxruntime.__version__} providers={onnxruntime.get_available_providers()}")
    print(f"opencv={cv2.__version__}")
    print(f"model_pack={settings.face_model_pack} det_size={settings.face_det_size} use_gpu={settings.face_use_gpu}")

    # Load (and, on first ever run, download) the SCRFD + ArcFace model pack.
    print("loading_model=...")
    face_engine.warmup()
    print("loading_model=ok")

    capture = cv2.VideoCapture(parse_source(arguments.source))
    if not capture.isOpened():
        print(f"camera_opened=False source={arguments.source}")
        return 1

    read_ok, frame = capture.read()
    capture.release()
    if not read_ok:
        print(f"camera_frame_read=False source={arguments.source}")
        return 1

    print(f"camera_opened=True source={arguments.source}")
    print(f"camera_frame_read=True shape={frame.shape}")

    faces = face_engine.detect_faces(frame)
    print(f"faces_detected={len(faces)}")
    for index, face in enumerate(faces, start=1):
        print(f"  face_{index} bbox={face.bbox} det_score={face.det_score:.3f} embedding_dim={len(face.embedding)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
