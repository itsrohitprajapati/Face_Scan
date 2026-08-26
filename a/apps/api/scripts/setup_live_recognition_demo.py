"""Create a full demo setup from one reference image and preview live face matching."""

from __future__ import annotations

import argparse
import sys
import uuid
from dataclasses import dataclass
from pathlib import Path

import cv2
import face_recognition
from fastapi.testclient import TestClient

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.main import app

MATCH_DISTANCE = 0.5


@dataclass
class DemoSetup:
    student_name: str
    class_id: str
    camera_source_id: str
    teacher_email: str
    teacher_password: str
    student_email: str
    student_password: str


def parse_source(value: str) -> int | str:
    return int(value) if value.isdigit() else value


def setup_demo(image_path: Path, source: str) -> DemoSetup:
    """Exercise the real API to create teacher, student, class, membership, and camera data."""
    image_bytes = image_path.read_bytes()
    suffix = uuid.uuid4().hex[:8]
    teacher_email = f"demo.teacher.{suffix}@example.com"
    student_email = f"demo.student.{suffix}@example.com"
    password = "demo-password-123"
    student_name = f"Recognition Demo {suffix}"

    with TestClient(app) as client:
        teacher_response = client.post(
            "/api/v1/auth/register/teacher",
            json={
                "full_name": "Recognition Demo Teacher",
                "email": teacher_email,
                "password": password,
                "invite_code": "SMART-TEACHER-DEMO",
            },
        )
        if teacher_response.is_error:
            raise RuntimeError(f"Teacher registration failed: {teacher_response.status_code} {teacher_response.text}")
        teacher_headers = {"Authorization": f"Bearer {teacher_response.json()['access_token']}"}

        files = [("photos", (image_path.name, image_bytes, "image/jpeg")) for _ in range(3)]
        student_response = client.post(
            "/api/v1/auth/register/student",
            data={
                "full_name": student_name,
                "roll_number": f"DEMO-{suffix}",
                "email": student_email,
                "password": password,
            },
            files=files,
        )
        if student_response.is_error:
            raise RuntimeError(f"Student registration failed: {student_response.status_code} {student_response.text}")
        student_headers = {"Authorization": f"Bearer {student_response.json()['access_token']}"}

        class_response = client.post(
            "/api/v1/classes",
            json={"name": "Live Recognition Demo", "section": suffix},
            headers=teacher_headers,
        )
        if class_response.is_error:
            raise RuntimeError(f"Class creation failed: {class_response.status_code} {class_response.text}")
        classroom = class_response.json()

        join_response = client.post(
            "/api/v1/classes/join",
            json={"join_code": classroom["join_code"]},
            headers=student_headers,
        )
        if join_response.is_error:
            raise RuntimeError(f"Student class join failed: {join_response.status_code} {join_response.text}")

        source_type = "webcam" if source.isdigit() else "ip_stream"
        camera_response = client.post(
            f"/api/v1/classes/{classroom['id']}/camera-sources",
            json={"label": "Live recognition demo camera", "source_type": source_type, "source": source},
            headers=teacher_headers,
        )
        if camera_response.is_error:
            raise RuntimeError(f"Camera creation failed: {camera_response.status_code} {camera_response.text}")

    return DemoSetup(
        student_name=student_name,
        class_id=classroom["id"],
        camera_source_id=camera_response.json()["id"],
        teacher_email=teacher_email,
        teacher_password=password,
        student_email=student_email,
        student_password=password,
    )


def preview_recognition(image_path: Path, source: str, student_name: str) -> int:
    """Show a live window using the same face-distance threshold as the attendance worker."""
    reference_image = face_recognition.load_image_file(image_path)
    reference_encodings = face_recognition.face_encodings(reference_image)
    if len(reference_encodings) != 1:
        print("The reference image must contain exactly one detectable face.")
        return 1

    capture = cv2.VideoCapture(parse_source(source))
    if not capture.isOpened():
        print(f"Could not open camera source: {source}")
        return 1

    print("Live recognition preview started. Press Q or Escape to close it.")
    try:
        while True:
            read_ok, frame = capture.read()
            if not read_ok:
                print("Could not read a camera frame.")
                return 1
            small_frame = cv2.resize(frame, (0, 0), fx=0.25, fy=0.25)
            rgb_frame = cv2.cvtColor(small_frame, cv2.COLOR_BGR2RGB)
            locations = face_recognition.face_locations(rgb_frame)
            encodings = face_recognition.face_encodings(rgb_frame, locations)

            for (top, right, bottom, left), encoding in zip(locations, encodings, strict=True):
                distance = float(face_recognition.face_distance(reference_encodings, encoding)[0])
                matched = distance < MATCH_DISTANCE
                label = f"{student_name} ({distance:.3f})" if matched else f"UNKNOWN ({distance:.3f})"
                color = (34, 197, 94) if matched else (0, 0, 255)
                top, right, bottom, left = (value * 4 for value in (top, right, bottom, left))
                cv2.rectangle(frame, (left, top), (right, bottom), color, 2)
                cv2.putText(frame, label, (left, max(28, top - 10)), cv2.FONT_HERSHEY_SIMPLEX, 0.65, color, 2)

            cv2.imshow("Smart Attendance — Live Face Recognition", frame)
            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), 27):
                return 0
    finally:
        capture.release()
        cv2.destroyAllWindows()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", default="../../student.jpg", help="One-face enrollment image path.")
    parser.add_argument("--source", default="0", help="Webcam index or IP-camera URL.")
    parser.add_argument("--no-preview", action="store_true", help="Create demo records without opening a camera window.")
    arguments = parser.parse_args()

    image_path = Path(arguments.image).resolve()
    if not image_path.is_file():
        print(f"Reference image does not exist: {image_path}")
        return 1

    setup = setup_demo(image_path, arguments.source)
    print("Demo setup complete.")
    print(f"class_id={setup.class_id}")
    print(f"camera_source_id={setup.camera_source_id}")
    print(f"teacher_email={setup.teacher_email} password={setup.teacher_password}")
    print(f"student_email={setup.student_email} password={setup.student_password}")
    if arguments.no_preview:
        return 0
    return preview_recognition(image_path, arguments.source, setup.student_name)


if __name__ == "__main__":
    raise SystemExit(main())
