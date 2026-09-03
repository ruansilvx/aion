---
ticketId: AIO-71
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-20T00:00:00.000
updatedAt: 2026-08-20T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Trash screen multi-select

## Key questions asked

1. Do you want both bulk actions (restore and permanent-delete), or is one less valuable — e.g. is bulk permanent-delete redundant with "Empty trash" already covering the all-at-once case, and the real pain point is bulk restore?
2. Reuse `TicketSelectionCubit` as-is (same state class, new selection-bar widget with Trash's two actions), or does Trash's selection warrant its own dedicated cubit/state?
3. For bulk Delete forever, should the confirm dialog state the aggregate count — selected roots plus their already-known `descendantCounts` (no extra repository call) — or is a plain "Delete N tickets?" (roots only) good enough?
4. Single-row Restore has no confirmation today (reversible, no friction). Should bulk Restore stay confirmation-free too, or get a lightweight confirm given it can hit many tickets at once?

## Summary of answers

1. Both — bulk restore and bulk permanent-delete are both wanted, not just one.
2. Reuse `TicketSelectionCubit` as-is. No new cubit/state type; only a new Trash-specific selection-bar widget wiring into the existing generic id-toggle state.
3. Aggregate count, using data already loaded (`TrashLoaded.descendantCounts`) — no new repository query needed for the confirm-dialog copy.
4. No confirm on bulk Restore — matches the existing single-row precedent; reversible actions don't get friction regardless of selection size.

## Conclusions reached

Clear direction: extend Trash with a `TicketSelectionCubit`-backed selection bar (screen-scoped around `/workspace/tickets/trash`, same pattern as `TicketsListScreen`'s `BlocProvider` wiring) exposing exactly two actions:

- **Bulk Restore** — `reversible`-tone action, no confirmation dialog, mirrors the single-row Restore's existing frictionless behavior.
- **Bulk Delete forever** — `destructive`-tone confirm dialog (via `showAppConfirmDialog`) stating the aggregate count: selected root count plus the sum of their `descendantCounts` (already loaded in `TrashLoaded`, no extra query), mirroring how "Empty trash"/"Purge old" already state exact counts.

Selection is inherently root-only, since `TrashLoaded` only lists trashed root tickets (descendants are folded into each root's "+N subtasks" count, not shown as separate rows). Both bulk actions cascade per-root the same way their existing single-ticket counterparts do (`restoreTicket`/`permanentlyDeleteTicket` already cascade to ancestors/descendants respectively) — bulk is just "do the existing cascade for each selected root," with no new cross-selection dedup concern, since two selected roots in Trash can never overlap (the cascade invariant guarantees a trashed root's subtree is disjoint from any other trashed root's subtree).

This requires two new batch surface methods that don't exist yet: `TrashCubit.restoreTickets(List<String> ids)` and `TrashCubit.permanentlyDeleteTickets(List<String> ids)`, backed by matching `TicketRepository`/`TicketParentTrashService` batch methods — mirroring the `trashTicket`/`trashTickets` singular-vs-batch split already established on `TicketsCubit`. The DAO layer already has the needed bulk primitives (`restoreByIds`, `deleteTicketRows`), so the new work is at the repository/service layer plus the two new `TrashCubit` methods and the UI wiring.

## Open questions

- Exact repository/service method signatures for the new batch restore/permanent-delete calls (left to `/propose`/`/design` — mechanical, not a product decision).
- Whether `TrashScreen`'s existing "Purge old"/"Empty trash" header actions need any UI adjustment to coexist with the new selection bar (e.g. do they become unreachable while selection mode is active, matching how `TicketsListScreen`'s `AppFab` is replaced by `TicketSelectionBar`?). Not asked this session — worth confirming during `/propose`.

## Architectural implications

- No new state-management pattern: this is a straight extension of the already-proven `TicketSelectionCubit` reuse established by [[bulk-status-and-priority-edit-for-ticket-selection]], just pointed at `TrashScreen` instead of `TicketsListScreen`.
- Reinforces the existing `reversible`/`destructive` `ConfirmDialogTone` convention rather than introducing a new one.
- Confirms the Trash cascade invariant (a trashed root's subtree never overlaps another trashed root's subtree) is sufficient to rule out any special-case dedup logic in the new batch methods — unlike `TicketsCubit.trashTickets`, which does need dedup since its input `ids` can include both ancestors and descendants of each other.