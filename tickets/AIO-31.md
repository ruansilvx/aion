---
ticketId: AIO-31
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-11T00:00:00.000
updatedAt: 2026-08-11T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Estimate/timeSpent rollup for ticket hierarchy

## Key questions asked

1. Is "rollup" just a sum of children's estimate/timeSpent shown read-only
   on the parent, or something more (e.g. divergence flagging)?
2. If a parent already has its own manually-entered estimate/timeSpent
   *and* has children, does the rollup replace that display, or add to
   it?
3. Does the rollup recurse through multiple levels, or only sum direct
   children one level down?
4. Should the rolled-up total be persisted into the ticket's markdown/
   resource file, or stay a purely computed, in-memory display value?
5. Since it's persisted, what triggers a recompute — immediate on every
   descendant change, or lazy (computed when the parent is viewed)?
6. Does recompute trigger only from in-app edits (Cubit-driven changes,
   reparenting), or also from hand-edited markdown files picked up by
   `TicketMarkdownWatcherService`?
7. Where does the rolled-up total actually show in the UI — detail
   screen only, or also list rows and board cards?
8. Risk check: does a cascading ancestor rewrite (Task → Story → Epic)
   from one triggering edit produce one git commit, or one commit per
   ancestor?

## Summary of answers

1. Simple sum — no divergence flagging, no extra semantics.
2. Additive: the parent's own manually-entered value is added into the
   sum alongside its children's, matching Jira's behavior.
3. Fully recursive through all levels — an Epic's total already reflects
   its Stories' own rolled-up totals (which already include their
   Tasks), not just direct children.
4. Persisted to disk, into the markdown/resource file — not purely
   computed/in-memory.
5. Immediate recompute on every triggering change, so the displayed
   number is always accurate when viewed — no lazy/on-open computation.
6. Both — in-app edits/reparenting *and* hand-edited file changes
   detected by `TicketMarkdownWatcherService` must trigger the same
   upward walk-and-rewrite.
7. Everywhere the ticket is displayed: detail screen, list rows, and
   board cards.
8. One git commit per triggering edit — all cascading ancestor rewrites
   from that single trigger batch into that same commit, not one commit
   per ancestor.

## Conclusions reached

Build a recursive, persisted estimate/timeSpent rollup:

- **Computation**: each parent's displayed estimate/timeSpent = its own
  field value (if set) + the recursive sum of all descendants' rolled-up
  values. Fully recursive, not one-level.
- **Persistence**: the rolled-up total is written into the parent
  ticket's markdown/resource file (not just held in memory), consistent
  with tickets.md's existing hand-editable file model.
- **Recompute triggers**: any estimate/timeSpent change anywhere in a
  ticket's ancestor chain — in-app edit, reparent operation, or a
  hand-edited file change detected by `TicketMarkdownWatcherService` —
  immediately walks upward and rewrites every ancestor's file. Per
  [[feedback_cubit_domain_logic]], this recompute/walk logic belongs in
  a Cubit, not pushed down into a repository or the watcher service
  itself.
- **Display surface**: rolled-up totals show everywhere a ticket
  appears — detail screen, list rows, board cards — so this touches
  multiple widgets and will need a design gate during `/propose`.
- **Commit behavior**: one git commit per triggering edit. All
  cascading ancestor file rewrites caused by that single trigger are
  batched into that same commit, not committed individually per
  ancestor. This directly informs — but does not fully resolve —
  `aion-arch/specs/projects.md`'s existing open "batch review commit
  coalescing" question; this idea assumes single-edit-cascade batching
  specifically, which that broader open question should stay consistent
  with once resolved.

## Open questions

- Exact Cubit/service boundary for the upward-walk-and-rewrite logic
  (which Cubit owns it, how it interacts with `TicketMarkdownWatcherService`
  and `TicketDbReconstructionService`) — left for `/propose` to design.
- Whether reparenting a ticket needs to update *two* ancestor chains in
  one commit (old parent chain loses the subtree's contribution, new
  parent chain gains it) — implied by "immediate, always accurate" but
  not explicitly walked through in this session.
- Interaction with the still-unresolved "batch review commit
  coalescing" open question in `aion-arch/specs/projects.md` — this
  idea's one-commit-per-trigger answer should be revisited if that
  broader question resolves differently.

## Architectural implications

- Touches `TicketsCubit` (or a related Cubit) for the recompute/walk
  logic — see [[feedback_cubit_domain_logic]].
- Touches `TicketMarkdownWatcherService` to trigger the same walk on
  hand-edited file changes, not just in-app edits.
- Touches ticket detail screen, list row widgets, and board card
  widgets — multi-widget UI surface, so `/propose` should expect the
  design gate to come back `PENDING`.
- Interacts with the existing reparenting known gap
  ("`TicketsCubit.getValidParentCandidates`/`getValidParentCandidatesForType`")
  and the git-commit-coalescing open question in `projects.md` — worth
  cross-referencing both during `/propose`.