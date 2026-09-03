---
ticketId: AIO-62
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-14T00:00:00.000
updatedAt: 2026-08-19T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Show a last updated timestamp on each ticket

## Key questions asked

1. Where should the timestamp actually show — list/board cards
   (glanceable, but already crowded — `TicketBoardCard`'s meta-chip row
   already packs id badge, title, `TypeChip`, `PriorityBadge`, rollup
   badge, status badge) or just the detail screen?
2. Relative time ("2 hours ago") or an absolute date/time?
3. Reuse the existing day-granularity `formatTrashedAge` helper
   (`lib/core/utils/relative_time_format.dart`, used by the Trash
   screen — `'today'`/`'yesterday'`/`'N days ago'`, computed once per
   build, no self-refresh) for consistency, or add a new finer-grained
   (minute/hour) formatter that reads more precise but risks staleness
   while the screen sits open?
4. Does the granular label need to actively tick while the screen is
   open, or is it fine if it only updates on the next unrelated
   rebuild?

## Summary of answers

1. Detail screen only — not list/board cards.
2. Relative time.
3. Add a new granular formatter, distinct from `formatTrashedAge`.
4. Active tick — the label should advance on its own while the screen
   is open (e.g. "2 minutes ago" → "3 minutes ago" without navigating
   away or triggering an unrelated rebuild).

## Conclusions reached

Show `Ticket.updatedAt` on `TicketDetailScreen` (likely inside
`TicketMetadataSection`, alongside the existing `estimate`/`timeSpent`
`InlineEditableField`s and rollup display — exact placement left for
`/propose`) only — list/board cards are explicitly out of scope, since
their meta-chip row is already crowded.

Format via a **new** granular relative-time helper (minute/hour
buckets, e.g. "2 minutes ago", "3 hours ago"), separate from the
existing day-granularity `formatTrashedAge`. Unlike `formatTrashedAge`,
this label must **actively tick** while `TicketDetailScreen` is open —
per [[feedback_debounce_belongs_in_cubit]], that periodic refresh must
be driven from the Cubit layer (e.g. `TicketsCubit`, already a single
app-wide instance per [[live-refresh-open-ticket-detail-screen]]), not
a widget-layer `Timer` in `TicketDetailScreen`'s state, even though
`TicketBoardCard`'s status badge and similar existing patterns don't
need this (they update on data change, not on the clock ticking).

No new live-refresh plumbing is needed for the *write* case — a
background write to `updatedAt` (e.g. an AI suggestion landing) already
re-emits the open detail screen via the shipped
[[live-refresh-open-ticket-detail-screen]] mechanism. What's new here
is specifically refreshing the label purely from elapsed wall-clock
time, independent of any write.

## Open questions

- Exact bucket boundaries for the new granular formatter (e.g.
  "just now" for under a minute, minute-level up to an hour, hour-level
  up to a day, then falling back to `formatTrashedAge`-style day
  granularity or an absolute date) — left for `/propose`.
- Exact placement/label within `TicketMetadataSection` and whether
  `createdAt` should ever join it — not discussed this session, scope
  stayed to `updatedAt` only per the original one-line capture.
- Tick interval and exact Cubit-layer mechanism (e.g. a
  `Timer.periodic` owned by `TicketsCubit` itself vs. some other
  ticking primitive) — left for `/propose`.

## Architectural implications

- New file: a granular relative-time formatter alongside
  `lib/core/utils/relative_time_format.dart`'s existing
  `formatTrashedAge`, not a modification of it — the two have different
  staleness/granularity requirements and existing call sites
  (`TrashedTicketTile`) shouldn't change behavior.
- First case of a Cubit-driven periodic UI tick in this codebase (as
  opposed to Cubit-driven debounce, already established via
  [[feedback_debounce_belongs_in_cubit]]) — `/propose` should design
  this explicitly rather than improvising it during `/apply`.
- Builds on the already-shipped
  [[live-refresh-open-ticket-detail-screen]] mechanism for the
  write-triggered refresh path; only the clock-triggered path is new.