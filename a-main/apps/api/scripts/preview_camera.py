"""Open a visual OpenCV preview for a webcam, IP stream, or video file."""

from __future__ import annotations

import argparse

import cv2


def parse_source(value: str) -> int | str:
    return int(value) if value.isdigit() else value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default="0", help="Camera index, IP-camera URL, or video-file path.")
    parser.add_argument("--title", default="Smart Attendance Camera Preview", help="Preview window title.")
    arguments = parser.parse_args()

    capture = cv2.VideoCapture(parse_source(arguments.source))
    if not capture.isOpened():
        print(f"Could not open camera source: {arguments.source}")
        return 1

    print("Preview running. Press Q or Escape in the preview window to close it.")
    try:
        while True:
            read_ok, frame = capture.read()
            if not read_ok:
                print("Could not read a frame; closing preview.")
                return 1
            cv2.imshow(arguments.title, frame)
            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), 27):
                return 0
    finally:
        capture.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    raise SystemExit(main())
