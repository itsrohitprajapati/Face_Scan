# AI-Powered Smart Classroom Attendance & Analytics System

## Overview

A local-first hackathon application for classroom attendance using a laptop webcam and a phone camera. Students self-onboard with three face photos, while teachers manage classes, camera sources, sessions, attendance corrections, and basic daily analytics.

## Goals

1. Recognize enrolled students independently from two camera feeds and merge duplicate sightings.
2. Compute Present, Late, and Absent status using transparent session rules.
3. Give teachers operational controls, explainable attendance intelligence, and downloadable integrity reports while students retain private access to only their own attendance.

## Core User Flow

1. An admin, teacher, or student creates an account from the shared login page.
2. The admin creates physical rooms and configures each room's camera sources.
3. A student captures three reference photos from their device camera, supplies name and roll number, and receives locally generated embeddings.
4. A teacher creates a class and shares its join code.
5. A student joins the class with that code.
6. The teacher selects a class, enters a valid room code, and starts a session using every enabled camera in that room.
7. Room camera workers log qualified sightings; the system derives attendance.
8. Teachers review or override a result; students view only their own history.

## Features

### Authentication and onboarding

- One sign-in entry point with role-based routing.
- Admin registration protected by a demo invite code; the admin manages physical rooms and assigns one or more cameras to each room.
- Teacher registration protected by a demo invite code. Teachers select a class and enter a room code to start attendance with all enabled room cameras.
- Student face enrollment from exactly three browser-camera captures; file upload remains an API fallback for testing.

### Attendance

- Laptop webcam plus phone IP-stream or recorded-video source.
- Independent per-camera recognition workers and five-second cross-camera de-duplication.
- One-minute presence windows: any confident sighting in a minute gives one student presence credit, regardless of camera count or repeated detections.
- Automated status uses coverage thresholds: Present at 70%+ within the grace period, Late at 70%+ after grace or 30–69.9%, and Absent below 30%.
- Ten-minute grace period distinguishes on-time Present from Late.

### Dashboards

- Admin room and camera management, room code regeneration, enabled-camera state, and current room occupancy.
- Teacher class, room-based session, attendance, correction, timeline, camera-zone, review-queue, integrity-report, and scoped natural-language attendance-query workflows.
- Teachers can ask explainable questions such as attendance today, on a date, between dates, by status, or for a named student within a selected owned class. The parser maps supported language to bounded filters; it does not generate or execute arbitrary SQL.
- Student personal attendance percentage and session history.

## Scope

### In Scope

- Admin-managed rooms, room-owned camera configuration and editing, room availability, and one-active-session room exclusivity.
- Multi-camera recognition, local enrollment-photo storage, PostgreSQL metadata, and basic daily analytics.
- Manual teacher attendance overrides with an audit trail.

### Out of Scope

- Engagement detection, geometric camera calibration, alerts, and real predictive or inferred multi-day trend analysis. Historical attendance may be filtered and summarized through the teacher query workflow, but the MVP does not make predictions or infer trends. The current camera-zone view is an operational source summary, not inferred seating or identity tracking.
- Hosted deployment and production-grade identity verification.

## Success Criteria

1. A student recognized by both cameras within five seconds yields one merged sighting.
2. A teacher can complete a live session and see correct Present, Late, and Absent results.
3. A student cannot access another student's records.
