# AI Workflow Rules

## Approach

Build the system in small, end-to-end feature units. The recognition-environment check is a hard first milestone before UI work.

## Scoping Rules

- Keep the MVP to enrollment, two feeds, attendance rules, and role dashboards.
- Prefer a verifiable vertical slice over speculative analytics.
- Do not add engagement, alerting, calibration, or cloud-deployment work without an explicit request.

## When to Split Work

Split work when it combines API persistence, recognition workers, and frontend flows without a verifiable intermediate step.

## Handling Missing Requirements

- Resolve missing product behavior in the relevant context file before implementing it.
- Record unresolved technical risks in `progress-tracker.md`.

## Protected Files

- Do not edit generated dependency files manually.
- Do not modify PostgreSQL data or local enrollment media through destructive commands without explicit confirmation.

## Keeping Docs in Sync

Update the relevant context file whenever architecture, storage, scope, UI conventions, or code standards change.

## Before Moving to the Next Unit

1. Verify the current unit through targeted tests or a manual path.
2. Keep context files and the progress tracker current.
3. Do not proceed past recognition setup until a local webcam proof succeeds.
