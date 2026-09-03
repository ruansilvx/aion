---
ticketId: AIO-36
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-18T00:00:00.000
updatedAt: 2026-08-18T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# List/Board view choice and column visibility persistence

## Key questions asked

1. What's actually motivating this — the view mode resetting to Board every time, or the fixed/unconfigurable column set, or both?
2. For column customization: hide only, reorder only, or both?
3. (Scope-fork check) Given the fixed-6-statuses read of the gap, does this session also need to touch `TicketStatus`'s underlying values/gating semantics, or stay display-only?

## Summary of answers

- Both halves of the known gap are wanted: the List/Board toggle should remember the user's last choice per project, and Board's column set shouldn't be permanently fixed.
- Full customization (hide *and* reorder), not just one or the other.
- This file stays scoped to the *display* layer: the 6 `TicketStatus` values and every piece of gating logic keyed on them (coding-execution trigger on `inProgress`, blocked-badge/gate on `blocked`, PR-flow on `inReview`, rollup on `done`) are completely unchanged. The much larger question — making `TicketStatus` itself a project-defined, non-fixed set — surfaced during this same session and was split out into its own idea, [[configurable-workflow-and-automation-engine]], because it's an order of magnitude bigger and touches code well beyond the Board screen.

## Conclusions reached

- **View-choice persistence:** `TicketsListScreen`'s List/Board toggle persists per-project, using the same mechanism as the existing `SharedPrefsTicketListFilterRepository`/`SharedPrefsTicketListSortRepository` (a sibling repository, per-project-keyed). The screen opens in whichever mode the project was last left in, instead of always Board.
- **Column visibility/order:** a project can hide/show and reorder which of the 6 fixed `TicketStatus` values (`backlog`/`todo`/`inProgress`/`inReview`/`done`/`blocked`) render as `TicketBoardView` columns. Persisted the same per-project way. Purely a rendering config — `TicketBoardView` still groups the caller's already-ordered/filtered ticket list by `status` exactly as it does today; only which groups get a rendered column, and in what order, changes.
- **Hidden-status tickets stay fully reachable.** Hiding a column from Board never hides or filters the underlying tickets — they remain visible in List view and via the existing status filter (`TicketFilterPopover`/`AppFilterChip`). No ticket data or gating behavior changes.

## Open questions

- Exact default column order/visibility for a freshly created project — presumably "all 6, current enum order" (today's behavior) as the out-of-the-box default, but left for `/propose` to confirm.
- Whether hiding a column should warn/indicate when tickets exist in that hidden status (e.g. a small overflow count), or stay silent — a `design-brief`/`design-sync` question, not architectural.
- Exact UI for reordering (drag-and-drop column headers vs. a Settings-style list reorder control) — implementation detail for `/propose`'s design.md.
- Whether Board's "Load more" button (`_BoardLoadMoreButton`) or pagination behavior needs any adjustment when fewer columns are visible — likely no, since pagination operates on the underlying ticket list, not rendered columns, but worth a sanity check during `/propose`.

## Architectural implications

- Extends the existing per-project `SharedPrefs*Repository` persistence pattern (`SharedPrefsTicketListFilterRepository`, `SharedPrefsTicketListSortRepository`) with a third sibling covering view-mode + column config — no new persistence mechanism invented.
- Touches `TicketsListScreen` (view-mode state moves from private widget state to Cubit/repository-backed), and `TicketBoardView`/`BoardColumn` (column set becomes a parameter instead of `TicketStatus.values` iterated directly).
- Deliberately orthogonal to [[configurable-workflow-and-automation-engine]] — that idea, if built, would supersede this one's "6 fixed statuses" assumption with project-defined statuses, but this idea is independently useful and buildable now regardless of whether that larger idea ever ships.