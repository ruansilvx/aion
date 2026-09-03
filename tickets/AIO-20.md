---
ticketId: AIO-20
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-19T00:00:00.000
updatedAt: 2026-07-20T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Consistent max-width, centered content layout convention

On wider screens, content is set to width, and it gets too stretched
out. Something similar to New Project page — limited width and
centralized — should be applied everywhere.

## Key questions asked

1. "Applied everywhere" for max-width centering — the board view
   specifically needs its multiple kanban columns to use available
   width to stay usable on a wide screen. Should the board be
   exempted from centering, or does it need a different treatment
   (e.g. centered but with a much larger max-width than detail/form
   screens)?

## Summary of answers

1. Exempt the board — kanban columns keep full width (they need the
   space to stay usable). Everything else — ticket detail, page
   detail, documentation content, forms, list views — gets a shared
   max-width + centering convention like `NewProjectScreen`'s.

## Conclusions reached

Adopt a shared max-width + centered-content layout convention:

- **Reference pattern**: `NewProjectScreen`
  (`features/projects/presentation/screens/new_project_screen.dart`)
  already does this —
  `ConstrainedBox(constraints: BoxConstraints(maxWidth: 520))` wrapped
  around its form content, with horizontal padding outside it. This
  becomes the model, likely promoted into a shared, reusable widget
  (e.g. a `ContentMaxWidth`/`CenteredContent` wrapper in
  `design_system/`) rather than copy-pasted per screen.
- **Scope — capped**: ticket detail, page detail, documentation
  content/reading view, all forms (create/edit screens), and list
  views (ticket list, documentation tree).
- **Scope — exempted**: the kanban board only, since its multiple
  columns need full available width on wide screens to remain usable.
- **Open sizing question** (left for `/propose`): whether one shared
  max-width value applies everywhere in the capped set, or different
  contexts get different caps (e.g. a narrower cap for forms like
  New Project's 520px, a wider cap for reading-oriented content like
  documentation pages or ticket detail).

## Open questions

- Exact max-width value(s) per context — implementation detail for
  `/propose`/`/design-sync`.
- Whether this becomes a single shared widget in `design_system/` or
  a documented convention enforced by review (similar to how
  internationalization was enforced via `flutter-conventions.md`
  rather than a lint rule, per [[use-internationalization-for-the-strings]]).
- Not addressed this session: three related bugs the user flagged
  (chevron shown on documentation pages with no children, markdown
  checkbox syntax not rendering, info bubbles like "synced" clipping
  near the viewport edge on Windows) — user explicitly deferred these
  out of this brainstorm to be handled as direct fixes, not design
  exploration.

## Architectural implications

- Likely a new shared `design_system/` widget/wrapper, used broadly
  across `features/tickets/` and `features/pages/` screens — a
  cross-cutting styling change, not tied to one feature module.
- Paired with [[persistent-navigation-shell]] from the same session —
  both are cross-cutting UX-consistency changes touching many screens
  at once. Could be proposed as one combined change or two sequential
  ones; left for `/propose` to decide based on scope (this one is
  smaller/lower-risk and could ship independently first).