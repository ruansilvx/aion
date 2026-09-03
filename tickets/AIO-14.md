---
ticketId: AIO-14
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-10T00:00:00.000
updatedAt: 2026-08-10T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Bulk status and priority edit for ticket selection

## Key questions asked

1. Of the three named in `tickets.md`'s known gap (status change, reparent,
   type/priority edit) — which one actually bites you day to day, or do
   you want to reason through all three first?
2. (Given "don't know yet") What was actually happening on screen the
   last time you had a pile of tickets selected and wanted to do one
   thing to all of them?
3. (User isn't using Aion yet, asked for guidance instead) Which of the
   named operations is a natural implementation, and which are more
   complex?
4. Given that complexity spread, does this session aim to scope down to
   a first slice now, or think through all four up front?
5. From a UX point of view, how should the two new bulk actions surface
   in `TicketSelectionBar` — inline icon buttons next to Delete, or a
   single "Actions" overflow trigger?
6. Confirm direction, plus: how should a bulk status write behave when
   the Blocked-dependency gate rejects some of the selected tickets but
   not others?

## Summary of answers

- User isn't using Aion day-to-day yet, so there was no lived pain point
  to anchor on — the session moved to a complexity/feasibility
  assessment instead, grounded in `aion-arch/specs/tickets.md`.
- Complexity assessed per operation:
  - **Priority edit** — trivial. Plain enum field, no structural
    constraints; bulk is just a batch write, same shape as the existing
    bulk-trash batch update.
  - **Status change** — easy. Single-ticket status writes already funnel
    through one method (`TicketsCubit.updateTicketStatus`) shared by
    drag, `MoveToStatusMenu`, and the detail screen. The only wrinkle —
    the Blocked-dependency gate can reject a write per-ticket — already
    has a precedent: `trashTickets` handles per-id partial success today.
  - **Reparent** — hard. A single ticket's valid-parent set already needs
    self/descendant exclusion, type-compatibility filtering, and cycle
    detection (`getValidParentCandidates`, itself a flagged perf gap:
    full in-memory scan, no caching). Bulk reparent would mean
    intersecting that valid set across every selected ticket at once —
    a real, unresolved UX question for mixed-type selections.
  - **Type edit** — hardest. Changing a ticket's type can invalidate its
    existing parent *and* existing children against the (not yet formally
    defined — see `define-type-compatibility-matrix`) type-compatibility
    rules. Bulk would multiply that cascade-checking across a whole
    selection.
- Decision: scope this idea to **bulk priority + bulk status only**.
  Bulk reparent and bulk type edit are explicitly rejected as not
  making sense for Aion in bulk form — a deliberate exclusion, not a
  deferral.
- UX direction: **inline icon-button triggers**, not an overflow
  "Actions" menu. With only three total actions (Delete, Status,
  Priority), hiding two behind an overflow tap adds friction for no
  space benefit. Each new button opens a `SelectionMenu<T>`-style
  overlay — the same pattern `TicketDetailScreen` already uses for its
  priority/type pickers — keeping the interaction cost at 2 taps, same
  as editing a single ticket today. Unlike `MoveToStatusMenu`'s
  single-ticket picker (which excludes the ticket's current status), the
  bulk pickers must list *all* values with nothing excluded, since a
  selection can span tickets with different current statuses/priorities.
- Blocked-dependency handling: bulk status writes follow existing
  precedent — the same per-id partial-success handling `trashTickets`
  already implements (each id succeeds or fails independently; no
  all-or-nothing rollback).

## Conclusions reached

Build bulk Status and bulk Priority edit on top of the existing
`TicketSelectionCubit`/`TicketSelectionBar` foundation (currently
Delete-only). Add two inline icon-button triggers next to the existing
destructive Delete button, each opening a `SelectionMenu<TicketStatus>`/
`SelectionMenu<TicketPriority>` overlay that lists all values with no
current-value exclusion. Bulk status writes respect the existing
Blocked-dependency gate per-ticket, using the same per-id partial-success
handling `trashTickets` already established. Bulk reparent and bulk
type edit are explicitly out of scope — ruled out, not deferred.

Ready for `/propose`.

## Open questions

- Exact toast copy/wording for a bulk status change with some tickets
  blocked and others succeeding — implementation detail for `/propose`.
- Whether the bulk priority picker needs a "clear priority" option
  (depends on `Ticket.priority`'s nullability) — check during `/propose`.
- Icon glyph choice for the two new `TicketSelectionBar` triggers —
  implementation detail.

## Architectural implications

- `TicketSelectionCubit`/`TicketSelectionBar`'s action surface grows from
  one action (Delete) to three (Delete, Status, Priority) — this
  establishes the pattern any further bulk action would follow, should
  one ever be proposed.
- Reuses `SelectionMenu<T>` for both new pickers rather than introducing
  new overlay widgets, consistent with the project's existing
  `Overlay`/`OverlayMenuItem` primitive-reuse convention.
- Formally narrows the "no bulk operations other than delete" known gap
  in `tickets.md`: once implemented, only bulk reparent/type edit remain
  unbuilt, and both are now recorded as deliberately excluded rather
  than open.
- Bulk write orchestration (per-id Blocked-gate check, partial-success
  aggregation) belongs in `TicketsCubit`, per
  [[feedback_cubit_domain_logic]] — reinforces that convention rather
  than introducing an exception.
- Bulk type edit's rejection is informed by the still-unresolved
  `define-type-compatibility-matrix` idea — if that matrix's direction
  changes substantially, this exclusion is worth revisiting.