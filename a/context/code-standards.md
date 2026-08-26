# Code Standards

## General

- Keep modules small and focused on one boundary.
- Validate untrusted input at API boundaries.
- Fix root causes rather than adding UI-only workarounds.

## TypeScript

- Enable strict mode.
- Avoid `any`; model API data with explicit types.
- Keep browser code free of recognition and database logic.

## Python / FastAPI

- Use type annotations and Pydantic request and response models.
- Keep route handlers thin; place business rules in services.
- Enforce authentication, role, and ownership before every protected operation.

## Styling

- Use the semantic design tokens defined in `ui-context.md`.
- Keep responsive behavior in Tailwind utility classes; avoid inline styles except computed layout values.

## API Routes

- Validate and parse request input before any business logic.
- Return consistent JSON error shapes.
- Never expose face embeddings, photo paths, password hashes, or another student's attendance to the browser.

## Data and Storage

- Store enrollment images on local disk, never as PostgreSQL blobs.
- Store relative image paths and face embeddings in PostgreSQL.
- Use database transactions for attendance and audit mutations.

## File Organization

- `apps/web/src/` — React routes, components, API client, and styles.
- `apps/api/app/` — API routers, models, schemas, services, and workers.
- `packages/contracts/` — cross-application contracts.
