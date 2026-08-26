# UI Context

## Theme

Clean, high-contrast academic operations dashboard. Responsive layouts prioritize an at-a-glance attendance state without hiding controls.

## Colors

Use Tailwind semantic utility classes backed by application CSS variables. Define the palette during web-app setup; avoid arbitrary colors in feature components.

## Typography

Use an accessible system sans-serif stack. Use tabular numerals for attendance metrics and timestamps.

## Border Radius

| Context | Class |
| --- | --- |
| Inline controls | `rounded-md` |
| Cards and panels | `rounded-xl` |
| Dialogs | `rounded-2xl` |

## Component Library

React components live within `apps/web/src/components/`. Build lightweight, accessible primitives locally; do not add a component-library dependency in the first MVP.

## Layout Patterns

- Shared authenticated shell with responsive navigation.
- Teacher views use summary metrics followed by actionable tables.
- Student views show personal metrics and chronological history.
- Forms show inline field validation and camera-source state.

## Icons

Use Lucide React where an icon materially improves comprehension.
