---
ticketId: AIO-32
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-19T00:00:00.000
updatedAt: 2026-08-20T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Generalized live-refresh for all ticket writes

## Key questions asked

1. Should this generalize `_refreshDetailIfOpenAndAffected` into a proper
   multi-level "walk up to any ancestor whose derived state depends on
   this write" check, or stay scoped to exactly the two concretely-named
   gaps (bulk writes wired through the existing direct-parent check, plus
   one more specific Epic-on-child-Story-sddStage check)?
2. Given that `sddStage` only ever changes via the explicit
   `advanceSddStage` action — never auto-derived from a child write, so
   today's dependency chain is always exactly one hop — does
   "generalize" still mean building arbitrary-depth ancestor-walking
   (future-proofing for a pattern that doesn't exist yet), or does it
   mean turning the current hardcoded Story-only check into a small
   table of `(parentType, childType, watchedField)` triples covering
   exactly the two known cases?
3. Now that a generic walker is being built anyway, should this change
   also audit and wire *every* `TicketsCubit` write path through it
   (parent reassignment, type reclassify, idea promotion, trash/
   restore), or stay scoped to just the write paths already known to
   cause the two named gaps (single/bulk status writes, bulk priority
   writes, `advanceSddStage`)?
4. Should the generic walker sit behind one central interception point
   (wherever `TicketsCubit` funnels writes through `TicketRepository`,
   so future write methods get this for free automatically), or should
   each public `TicketsCubit` method keep explicitly chaining the check
   onto its own completion, as today's two call sites do?

## Summary of answers

1. Generalize — future-proof, not just the two named cases.
2. Confirmed via the actual code semantics (`advanceSddStage` is the
   only writer of `sddStage`, [tickets.md:1908](../specs/tickets.md)):
   the dependency chain is genuinely always one hop today. "Generalize"
   means a declarative `(parentType, childType) → watched field` table
   plus a generic one-hop walker, not literal N-level traversal logic —
   though the walker's shape (re-triggering the same check at each level
   a write lands) means a future cascading write would get correct
   multi-hop propagation for free, with zero new live-refresh code.
3. Wire every write path, not just the two symptomatic ones — directly
   resolves the open question the sibling
   `live-refresh-open-ticket-detail-screen` idea left dangling ("whether
   any other background-mutating path... should also be swept into the
   same general mechanism").
4. Central interception point — not per-method manual chaining. Any
   write method added later (including ones this session didn't
   enumerate) is covered automatically, rather than depending on every
   future contributor remembering to wire a new call site by hand.

## Conclusions reached

Replace `_refreshDetailIfOpenAndAffected`'s two hardcoded cases with:

- **A declarative dependency table** — `(parentType, childType) →
  watched field` — seeded with the two known pairs:
  `story ← task/bug.status` (already live) and `epic ← story.sddStage`
  (the named gap). No field-diffing needed: re-fetching an already-open
  `TicketDetailLoaded` ticket is cheap/idempotent (same-id Loading-skip
  already prevents spinner flash), so the check only needs to match
  ticket *types* and relationship, not compare old/new field values.
- **A generic one-hop walker**: given a written ticket, resolve its
  parent, look up `(parent.type, writtenTicket.type)` in the table, and
  if the currently-open `TicketDetailLoaded` ticket is that parent,
  refresh. Because every field this table would ever watch is itself
  only ever changed by an explicit write (never silently auto-derived —
  confirmed for `sddStage` via `advanceSddStage`, and true of `status`
  writes too), one hop is always correct for today's two pairs. A
  future cascading write (e.g. if Aion ever auto-advances a Story's
  `sddStage` on child completion) would re-enter this same central
  check at the next level up automatically — true multi-hop
  propagation without new live-refresh code, which is the actual
  future-proofing payoff, not upfront N-level graph traversal.
- **One central interception point**, not per-call-site chaining:
  wherever `TicketsCubit` funnels every write through
  `TicketRepository`, hook the walker there. This automatically covers
  bulk status/priority writes ([Bulk status/priority
  edit](../specs/tickets.md#bulk-statuspriority-edit)), `advanceSddStage`,
  and every other write method (parent reassignment, idea promotion/
  reclassify, trash/restore) — both closing the two gaps named in
  [tickets.md:6957-6964](../specs/tickets.md) and removing the need for
  any future write method to remember to wire itself in.

Ready for `/propose`.

## Open questions

- Whether `TicketsCubit` already funnels every write through one shared
  low-level method today, or whether introducing that choke point is
  itself part of this change's scope — needs a direct code read, not
  just the spec prose, during `/propose`.
- Whether trash/restore and parent-reassignment writes actually belong
  in the dependency table — e.g. does trashing a Task change what
  `_sddStageAdvanceCheck` sees as a Story's live children set? Needs
  precondition-semantics verification against the actual implementation.
- Whether the table should ship at `/propose` time with just the two
  known pairs, or whether `/propose` should also audit for other
  undiscovered direct-parent-derived-state dependencies while the
  mechanism is being built (e.g. `needsDesignReview`,
  `estimateRollup`/`timeSpentRollup` — the latter already has its own
  recursive `computeRollups` mechanism per
  [tickets.md:6751-6759](../specs/tickets.md), which may or may not want
  folding into the same table rather than staying a separate
  computation).

## Architectural implications

- Touches `TicketsCubit` only, same as the mechanism it replaces — no
  new widget, no DB migration, no new provider/service. Consistent with
  [[feedback_cubit_domain_logic]]: this dependency table and its walker
  are display/orchestration judgment, which belongs in the Cubit, not
  pushed into `TicketRepository`.
- Directly resolves the open question left dangling by
  [[live-refresh-open-ticket-detail-screen]] ("whether any other
  background-mutating path... should also be swept into the same
  general mechanism") — this idea answers it: yes, via a central
  interception point rather than auditing call sites by hand.
- Also closes the wiring half of [[bulk-status-and-priority-edit-for-ticket-selection]]'s
  shipped feature — that idea built the bulk write path itself but
  never wired it to live-refresh, since the live-refresh mechanism
  didn't exist yet at the time it shipped.
- Introducing a central write-interception point in `TicketsCubit` (if
  one doesn't already exist) is itself a structural change worth
  flagging to `/propose` explicitly, since it affects how every future
  write method in this Cubit gets written, not just this feature's own
  code.
- Raises, but doesn't resolve, whether `estimateRollup`/`timeSpentRollup`'s
  existing separate recursive `computeRollups` mechanism should
  eventually be folded into the same generic table/walker rather than
  remaining a parallel, differently-shaped computation — left as an
  open question above rather than decided here.