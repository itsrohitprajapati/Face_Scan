# Architecture Context

## Stack

| Layer | Technology | Role |
| --- | --- | --- |
| Web | Vite, React, TypeScript, Tailwind CSS, browser `getUserMedia` | Admin room/camera operations, teacher attendance operations, student enrollment and history |
| API | FastAPI, SQLAlchemy | REST API, authentication, session orchestration |
| Recognition | Python, face_recognition, OpenCV | Enrollment encoding and independent camera workers |
| Database | PostgreSQL via Docker Compose | Users, classes, sessions, sightings, attendance, audit events |
| Media | Local `apps/api/storage/` | Enrollment photo files |

## System Boundaries

- `apps/web/` owns browser UI and API consumption only.
- `apps/api/` owns authentication, persistence, recognition, attendance rules, camera workers, and bounded live preview frames.
- Teacher camera previews reuse the recognition worker's latest JPEG frame through a teacher-authenticated endpoint; they never open the configured camera a second time.
- `packages/contracts/` owns shared API contract documentation and types.
- `context/` owns the current product and engineering specification.

## Storage Model

- PostgreSQL: user profiles, password hashes, classes, memberships, face-encoding metadata, camera settings, sessions, sightings, attendance, audit events, and teacher attendance-assistant query results derived at request time. The OpenRouter provider receives only the teacher's natural-language question, bounded class context, and returned attendance summary; it never receives database access or biometric data.
- **Local media storage**: the three uploaded enrollment photos per student. Database rows retain safe relative paths.

## Auth and Access Model

- Every request is authenticated by a local account token.
- A stored user role determines teacher or student UI and API access.
- Admin registration uses a configured invite code and only one admin account is permitted in the local MVP. Admins exclusively manage rooms and their camera sources.
- Teachers select a class and provide an active room code when starting each session. A room can have only one active session; every enabled camera assigned to that room starts automatically.
- Legacy class-owned camera rows remain nullable and read-only for historical sighting integrity. New sessions and camera configurations are room-owned; teachers cannot mutate cameras.
- Students may read only their own profile, memberships, and attendance. Teachers may manage only their own classes and sessions.

## Invariants

1. Camera workers are independent and communicate only through persisted sightings; attendance collapses sightings into one credit per student per one-minute window.
2. Raw automated attendance is never overwritten by a teacher correction; corrections create immutable audit events.
3. A match at face distance `>= 0.5` cannot create a student sighting; it may create only an anonymous camera/timestamp event, rate-limited to once per camera every five seconds. Anonymous events do not enter attendance until an owning teacher explicitly assigns an event to an enrolled class student; attribution is append-only and does not mutate the source event.
4. Enrollment images remain local and embeddings are generated before a student can participate in attendance.
5. Live preview storage is bounded to one in-memory compressed frame per active camera and is removed when its session stops.
6. Camera health is bounded to last-frame timestamps and status per active source; it is not persisted as a frame history.
7. Teacher insight and report routes are scoped through the owned session and never expose embeddings, face images, or biometric file paths.
8. The natural-language attendance assistant is teacher-only and uses OpenRouter tool calling. The model may request only a bounded attendance search; the API validates dates, status, student/class scope, and teacher ownership before querying PostgreSQL. Provider credentials remain server-side and the feature is disabled when no API key is configured.
