# Progress Tracker

## Current Phase

- Phase 5 web MVP implemented — ready for browser-based end-to-end verification

## Current Goal

- Verify authentication, browser-camera enrollment, classroom operations, attendance sessions, and manual corrections through the React UI.

## Completed

- Product scope, architecture, attendance rules, UI direction, and monorepo structure agreed.
- Context templates populated with the current specification.
- Created the monorepo workspace layout, Docker Compose PostgreSQL service, environment templates, API dependency manifests, and media-storage boundary.
- Created the isolated API virtual environment; compiled dlib 20.0.1; installed and verified FastAPI, face_recognition, and OpenCV imports.
- Added a repeatable local recognition and camera-source verification script.
- Started and verified the local PostgreSQL Docker service; it is healthy and accepting connections on port 5432.
- Verified physical laptop webcam access locally: camera index `0` opened successfully and produced a `640×480` frame.
- Implemented FastAPI configuration, PostgreSQL schema creation, CORS, and a health endpoint.
- Implemented JWT authentication, role-protected current-user resolution, teacher invite-code registration, and email/password login.
- Implemented student multipart onboarding with exactly three JPEG/PNG photos, local photo persistence, one-face-per-photo validation, and stored embeddings.
- Verified API startup, OpenAPI auth routes, health response, and Ruff static checks against the local PostgreSQL service.
- Corrected the student-upload OpenAPI schema so Swagger renders `photos` as binary file inputs rather than text strings.
- Implemented teacher-owned classes, unique join codes, student class memberships, and role-aware class listing.
- Implemented teacher-only camera-source create, list, and update APIs supporting webcam indexes, IP-camera URLs, and video-file paths.
- Connected camera-source updates to the teacher UI, including edit, enable, disable, and protected delete controls.
- Connected live sightings polling to a bounded recent-detections panel in the teacher workspace, including recognized students and anonymous unknown faces.
- Verified the new ORM mappings, database table creation, API startup, OpenAPI class routes, and Ruff checks against PostgreSQL.
- Implemented attendance-session, sighting, and automated attendance-record persistence.
- Implemented one independent OpenCV/face-recognition worker per enabled camera source, sampled once per second with a face-distance threshold below `0.5`.
- Implemented five-second cross-camera (not same-camera) de-duplication and final Present/Late/Absent calculation using the agreed rolling five-minute, three-sighting rule.
- Added a teacher-only live-sightings endpoint for recognition verification before a session ends.
- Added an OpenCV camera-preview utility to visually validate webcam, IP-stream, and video-file sources outside the attendance worker.
- Added a disposable end-to-end demo setup and annotated live-recognition preview script using `student.jpg` as three enrollment references.
- Updated the demo setup script to generate validator-compatible demo email addresses and expose API validation details when setup fails.
- Decided that the React student onboarding flow will capture three photos directly from the browser camera; API file upload remains a fallback and test interface.
- Verified session API table creation and routes, Ruff checks, and deterministic attendance qualification logic.
- Implemented teacher attendance correction as append-only audit events; automated results remain unchanged while attendance responses expose effective status and full override history.
- Verified the correction table, OpenAPI route, Ruff checks, and Python compilation against the local PostgreSQL service.
- Manually verified Phase 4 live recognition and attendance workers with enrolled reference images and a camera source.
- Scaffolded the Vite, React, strict TypeScript, Tailwind CSS, and Lucide web application with semantic design tokens and responsive layouts.
- Implemented JWT session restoration, shared login, teacher registration, and role-based teacher/student workspaces.
- Implemented student registration with browser `getUserMedia`, exactly three camera captures, review thumbnails, and multipart API submission.
- Implemented teacher class creation, join-code copying, camera-source setup, session start/stop controls, session history, attendance review, and manual correction dialogs.
- Implemented student class-code joining and membership cards.
- Added an explicitly typed API client for existing authentication, class, camera, session, sighting, attendance, and override contracts.
- Enlarged student enrollment camera preview for better self-framing and added camera/upload/mixed enrollment options with retake controls.
- Reduced recognition sampling and preview latency by separating continuous frame reads from face-processing intervals and adding a one-frame capture buffer hint.
- Added recognized-name and unknown-face overlays directly to teacher preview frames, including color-coded face boxes.
- Added a teacher camera-source selector so every enabled recognition worker, including IP streams and video files, can be viewed during an active session.
- Added source-type labels, aspect-preserving preview rendering, and a reachability hint while waiting for an IP/file source frame.
- Verified the multi-source preview UI with strict TypeScript, Vite build, and `git diff --check`.
- Added student-only attendance history and summary analytics with membership ownership checks; effective statuses reflect latest teacher corrections without exposing other students.
- Connected the student dashboard to attendance percentage, attended/late/session metrics, and per-session history.
- Added teacher-controlled attendance window size (1, 2, 5, 10, 15, 30, or 60 minutes) and arrival grace inputs to session setup; both values are persisted on the session and fixed after start for reproducible review.
- Updated presence coverage to calculate eligible and observed windows from each session's configured `qualification_window_minutes` instead of always using one-minute buckets.
- Unknown faces are persisted as anonymous, rate-limited sightings in teacher logs without images, embeddings, or identity data. Completed-session review shows a student dropdown for each unknown event; the original event remains anonymous, an append-only assignment records teacher attribution, and the review status is recalculated from the assigned minute window.
- Made attendance correction reasons optional in the UI and API; an empty reason is stored as `Teacher correction`, keeping the audit event valid while ensuring Save is always available.
- Updated product and architecture context to document the minute-window attendance model.
- Added teacher session insights derived from sightings: timeline replay, camera-zone summaries, bounded camera health, first/last-seen explanations, arrival/departure review signals, and a prioritized review queue.
- Added a teacher-owned CSV integrity report route and dashboard download action without exposing biometric data.
- Added a teacher-only natural-language attendance assistant using OpenRouter tool calling. The UI supports questions about dates/date ranges, students, statuses, and selected classes; the API executes only a bounded, ownership-checked attendance search and returns explainable filters, aggregates, and rows.
- Added server-side OpenRouter configuration (`OPENROUTER_API_KEY`, model, base URL), runtime dependency, provider privacy boundary documentation, and disabled-by-default behavior when no key is configured.
- Verified repository Ruff checks, Python compilation, TypeScript/Vite production build, and `git diff --check` after the assistant implementation.
- Formatted teacher assistant answers in the frontend with local heading, emphasis, list, and simple table rendering while retaining the canonical structured attendance result table. Renamed the action to Ask AI and added an accessible animated gradient/loading treatment with reduced-motion support.
- Added invite-code-protected single-admin authentication and role routing.
- Added admin-managed physical rooms with permanent regeneratable codes, active/inactive state, occupancy, and room-owned camera CRUD.
- Moved new attendance sessions to room-code startup: teachers select a class, enter a room code, and all enabled room cameras run automatically. One room permits only one active session.
- Removed new-session dependence on teacher-managed class cameras. Legacy class-camera rows remain nullable and untouched for historical sighting integrity; teacher room cameras are read-only.
- Added compatibility startup updates for the admin role and nullable room links without destructive database resets.
- Updated camera previews, recognition workers, camera-zone insights, and health lookup to use room cameras for room-based sessions while retaining legacy fallbacks.
- Fixed existing-database admin registration failures: compatibility startup now normalizes the PostgreSQL enum label to SQLAlchemy's `ADMIN` name instead of leaving a lowercase `admin` label that caused 500 responses. Verified admin registration requests return CORS headers and complete successfully on a migrated local database.
- Fixed existing-database room camera creation failures by also dropping the legacy `camera_sources.class_id` NOT NULL constraint when adding room ownership. Verified room camera creation returns `201 Created` with CORS headers.
- Added an admin camera-edit dialog for room cameras, including label, source type, source value, and enabled-state updates. Updated the README and product flow documentation for the latest admin-managed room workflow.
- Refactored the web frontend out of the monolithic `App.tsx` into focused auth, admin, teacher, student, and shared UI component modules while preserving existing flows and API contracts. `App.tsx` now owns only session restoration, role routing, and the authenticated shell.
- Made the teacher registration invite-code field visible and required, with client-side submission blocking when the code is empty.
- Added email-or-roll-number login: all roles retain email login, and students can authenticate with their unique roll number and password through the same bounded login endpoint.
- Added guided student enrollment capture using MediaPipe Face Landmarker: the browser guides the student through front, left, and right poses, automatically captures stable poses, supports review/removal and scan-again, and retains three-image upload as a fallback.
- Improved mobile enrollment camera UX with an explicit stop-camera control and portrait-friendly, non-cropped camera framing while preserving the wider desktop layout.
- Verified the frontend refactor with the strict TypeScript check, Vite production build, and `git diff --check`.

## In Progress

- Browser verification of one-minute coverage results, including a 50/60-minute example and multi-camera same-window deduplication.
- Browser verification of the refactored frontend flows and responsive layouts, including guided MediaPipe enrollment capture and upload fallback, admin room management, teacher sessions/review, and student history.
- Browser verification of the timeline, camera health, review queue, CSV integrity report, camera-source deletion safeguards, and rate-limited unknown-face logs.

## Next Up

- Verify anonymous unknown-face events with a live camera, including five-second per-camera throttling and exclusion from attendance coverage.
- Verify the browser camera preview and uploaded image paths on desktop and mobile-sized layouts.
- Verify the teacher preview with the local webcam during an active recognition session.
- Verify the one-minute coverage calculation with a completed 60-minute session and multiple camera sources.
- Verify the teacher/student coverage fields and README flow against the running services.
- Refine any threshold or camera-availability behavior found during browser testing.

## Open Questions

- None.

## Architecture Decisions

- One Vite React application routes users by stored role.
- FastAPI owns recognition workers and REST APIs; PostgreSQL runs locally through Docker Compose.
- Enrollment photos are local files; embeddings and metadata live in PostgreSQL.

## Session Notes

- `face_recognition_models` requires `setuptools<81` because it still imports `pkg_resources`; this compatibility pin is captured in `apps/api/requirements.txt`.
- Camera sources are web-app configuration managed by teachers. OpenCV supports local indexes, IP-camera URLs, and video-file paths through the same source field.
- Live student enrollment and recognition have been manually verified with real reference images and a camera source; local biometric media remains untracked and must not be committed.
- Start a session only after a class has at least one enabled camera source; recognition workers run inside the FastAPI process and stop when the session stops or the API shuts down.
