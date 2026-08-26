"""Verify the local dependencies and a configured OpenCV camera source."""

from __future__ import annotations

import argparse

import cv2
import dlib
import face_recognition


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

    print(f"dlib={dlib.__version__}")
    print(f"face_recognition={face_recognition.__version__}")
    print(f"opencv={cv2.__version__}")

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
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
