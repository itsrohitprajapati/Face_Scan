# Face Scan — Android

360°-guided face scan → on-device face embedding (MobileFaceNet/FaceNet
TFLite) → printed to the debug console.

This folder contains the **complete `lib/` app, `pubspec.yaml`, and a full
hand-written `android/` project** (manifest, Gradle files, MainActivity).
It was written outside of Flutter (no Flutter SDK / internet access in the
build sandbox), so before first run you need to let Flutter regenerate the
two things it always auto-generates locally:

## Two apps in one

This project is now a **Smart Classroom Attendance client** that talks to the
FastAPI backend in `a-main/`, with the original **360° face-embedding demo**
kept as a standalone tool.

- **Attendance app (default flow):** launch → sign in / register → role
  dashboard.
  - *Teachers* register with an invite code, create classes, and share join
    codes.
  - *Students* register with their roll number and **3 face photos** (captured
    in-app, validated to contain exactly one face each), join classes by code,
    and view their attendance %, Present/Late/Absent counts, and session
    history.
  - Point the app at your backend from the login screen's **Server settings**
    (default `http://10.0.2.2:8000` for the Android emulator; use your
    machine's LAN IP from a physical device — the `/api/v1` suffix is added
    automatically).
- **Face embedding demo:** reachable from the login screen via *"Try the face
  embedding demo"* — the 360° scan described below that prints an embedding to
  the console.

Student-registration photos are uploaded to `POST /auth/register/student`; the
backend derives and stores the face embeddings, so the same records power the
web dashboards and recognition workers.

> **Where matching actually happens.** Attendance recognition runs entirely on
> the backend (`a-main/`) using **InsightFace** — SCRFD face detection + landmark
> alignment + ArcFace 512-d embeddings — over the room's CCTV/IP cameras. The
> on-device **MobileFaceNet** model below powers only the standalone 360°
> embedding demo; it is not used for attendance and its vectors are never sent
> to the server (the app uploads the three enrollment photos and the backend
> computes the embeddings).

## 1. One-time setup

```bash
# from this folder
flutter create --platforms=android --org com.example -a kotlin --project-name face_scan_android .
```

Run this **once**, in this exact folder — `flutter create` will not
overwrite the `lib/`, `pubspec.yaml`, or `android/` files already here
(it only fills in things that are missing, like launcher icons,
`android/local.properties`, and the Gradle wrapper jar). If it ever asks
to overwrite a file, say **no**.

Then:

```bash
flutter pub get
```

## 2. Add a face embedding model

Drop a MobileFaceNet or FaceNet `.tflite` model (112×112 RGB input,
~128–512-d embedding output) at:

```
assets/models/mobilefacenet.tflite
```

Until you do, the app still runs end-to-end using a deterministic stub
embedding (clearly logged as such) so you can test the camera/pose/print
pipeline first. Search "mobilefacenet.tflite" — several MIT/Apache-licensed
conversions are available; if your model's input size or output dimension
differs, update `inputSize` / `outputSize` in
`lib/services/embedding_service.dart`.

## 3. Run

```bash
flutter run
```

## What it does

1. Home screen → **Start face scan** (requests camera permission).
2. Front camera opens with `google_mlkit_face_detection` running live on
   the frame stream, reading `headEulerAngleY` (yaw) / `headEulerAngleX`
   (pitch).
3. You're guided through 5 poses that together cover a full head
   rotation: **Center → Left → Right → Up → Down**. Each is auto-captured
   the moment your head is in range — no button mashing.
4. Once all 5 are captured, every crop is run through the TFLite model
   and averaged + L2-normalized into one identity embedding.
5. The embedding is printed to the console as:
   ```
   === FACE_EMBEDDING (dim=192) ===
   [0.041233, -0.118820, ...]
   ```
6. A result screen shows a short preview of the vector.

## Theme

Colors/typography in `lib/theme.dart` are mapped 1:1 from the supplied
CSS tokens (`--green #146c4a`, `--canvas #f6f7f4`, `--ink #17201c`,
Inter font, etc.), and `lib/widgets/gradient_action_button.dart`
recreates the animated `.ask-ai-button` gradient/sheen.

## Notes

- Minimum SDK is 23 (required by CameraX / ML Kit / TFLite deps).
- No launcher icons are included — `flutter create` (step 1) generates
  the default ones; swap them via `flutter_launcher_icons` if you want
  custom branding.
- Face embeddings are biometric data — handle/store them per your
  applicable privacy laws; this sample only prints to console and keeps
  nothing on disk.
