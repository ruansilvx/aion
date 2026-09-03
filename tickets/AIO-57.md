---
ticketId: AIO-57
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
# Reconciler applies hand-edited parentId/deletedAt changes

## Key questions asked

1. Is the goal to make the reconciler actually apply hand-edited
   `parentId`/`deletedAt` edits, or just to surface that they're being
   silently dropped?
2. Should the reconciler reach the missing safety logic (cycle-prevention,
   trash/restore cascade) via a `TicketsCubit` reference, or should that
   logic move down into `TicketRepository` so both callers can use it
   independently?
3. (Reconsidered) Confirmed: `TicketsCubit` reference, not a repository
   move.
4. When the Cubit rejects a hand-edited value (invalid parent, cycle,
   wrong type), should the ticket flip to `needsRepair` or silently keep
   falling back to the DB's existing value as it does today?
5. Is `TicketsCubit` actually reachable at the point `WorkspaceShell`
   constructs the reconciler/watcher, so wiring it through is a small
   constructor change or a bigger restructuring?
6. Given the wiring turned out to be real rework, should this be one
   change or split into a wiring change plus a behavior change?

## Summary of answers

1. Actually apply the edits — the reconciler should run the same
   cycle-prevention/cascade logic the UI's edit paths use, not just
   report that it can't.
2. Initially "move to the repository," then reconsidered: give the
   reconciler a `TicketsCubit` reference instead. This keeps domain
   logic (cycle-prevention, trash/restore cascade) in the Cubit per
   the existing [[feedback_cubit_domain_logic]] convention, rather than
   reversing it for these two fields.
3. — (see above)
4. `needsRepair` — same treatment as an `Unparseable` file, so a
   rejected hand-edit is visible to the user instead of silently
   discarded.
5. Checked `aion/lib/core/routing/app_router.dart`'s `WorkspaceShell`
   (lines 419–637): `TicketMarkdownReconciler` is built by a
   `RepositoryProvider` inside `MultiRepositoryProvider`, above
   `BlocProvider<TicketsCubit>` in the widget tree, and
   `TicketMarkdownWatcherService` is constructed and started in an outer
   `Builder` *before* `BlocProvider<TicketsCubit>` builds its subtree —
   so no `context.read<TicketsCubit>()` is available where the reconciler
   is currently created. Reaching the Cubit requires moving the
   reconciler's construction (or at least the point it's handed the
   Cubit) down into a scope where `TicketsCubit` already exists — e.g.
   the inner `Builder` alongside where `PageTicketProvider` already reads
   `context.read<TicketsCubit>()` — plus rethinking how
   `_watcherService`'s lifecycle-driven start/stop (currently a plain
   `State` field managed outside any Cubit-aware `Builder`) fits that.
6. Keep it as one change — the wiring restructuring and the new
   apply-on-reconcile behavior aren't independently useful; the wiring
   only exists to serve the behavior.

## Conclusions reached

Build this as a single OpenSpec change: `TicketMarkdownReconciler` gets a
`TicketsCubit` reference (via restructured `WorkspaceShell` provider/build
order, so the Cubit exists before the reconciler is constructed) and, on
detecting a changed `parentId` or `deletedAt` in a hand-edited
`resource`/`page` file, calls the same `TicketsCubit` methods the UI uses
(`updateTicketParent`, `trashTicket`/`restoreTicket`) rather than applying
a bare field write. If the Cubit rejects the value (cycle, invalid/missing
parent, wrong type), the ticket's `syncStatus` flips to `needsRepair`,
matching the existing `Unparseable` treatment, instead of silently
keeping the DB's old value. Domain logic (cycle-prevention, cascade)
stays in `TicketsCubit`, not pushed down into `TicketRepository`.

## Open questions

- Exact shape of the `WorkspaceShell` restructuring (where precisely the
  reconciler's construction/Cubit-handoff moves, and how
  `_watcherService`'s app-lifecycle start/stop reconciles with that) is
  left to `/propose`'s design.md, not resolved here.
- Whether a rejected hand-edit should also get any user-facing messaging
  beyond the existing `needsRepair` sync-status treatment (e.g. what
  `TicketRepairService`/the repair UI shows for a rejected `parentId` vs.
  an `Unparseable` file) is unexplored — `/propose` should check what
  `needsRepair`'s UI already surfaces before assuming it's sufficient.

## Architectural implications

Reinforces [[feedback_cubit_domain_logic]] — cycle-prevention and
trash/restore cascade logic stay in `TicketsCubit`, not
`TicketRepository`, even for a caller (the reconciler) that isn't a
widget. Requires restructuring `WorkspaceShell`'s provider/build order
(`aion/lib/core/routing/app_router.dart`) so `TicketMarkdownReconciler`
is constructed after `TicketsCubit` exists in scope — touches the same
file `page-nesting-depth-limit` and other recent changes have not, so
this is new territory for that file's provider ordering. Directly
resolves the two "Reparenting via a hand-edited file's parentId is not
applied" / "Restoring a deletedAt change... is not applied" gaps
documented in `aion-arch/specs/tickets.md`'s Known Gaps section.