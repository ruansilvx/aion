---
ticketId: AIO-13
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-24T00:00:00.000
updatedAt: 2026-07-28T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# New ticket type — Bug

## Key questions asked

1. What's the core distinction that makes Bug worth a new `TicketType`
   rather than just a Task with a label/tag?
2. Which fields should Bug actually have?
3. Where should Bug sit in `TicketTypeHierarchy` — ranked like Task, or
   parentless like `signal`/`release`?
4. Should every existing `TicketType.task` coding-execution check site
   widen to "task or bug," with full behavioral parity?
5. Should Bug's "affected version/environment" field be plain freeform
   text, or a formal `relatesTo` link to the existing Release ticket type?

## Summary of answers

1. **New fields needed** — Bugs need real structured data (severity,
   repro steps, expected/actual, affected version) that would be awkward
   to bolt onto Task's shape for every non-bug Task. Not just a
   filtering/visual distinction.
2. **All four**: severity (distinct from the existing `TicketPriority`,
   which is scheduling urgency, not impact severity), steps to
   reproduce, expected vs. actual behavior, and affected
   version/environment.
3. **Ranked like Task** — slots in at the same structural rank, can be
   parented under a Story or directly under an Epic, shows up on the
   Board in the same status columns, and triggers coding-execution the
   same way Task does when moved to `inProgress`. A bug is fundamentally
   a unit of execution with extra diagnostic fields, not a
   parentless-report type like `signal`/`release`.
4. **Yes, full parity** — every coding-execution mechanic (design-review
   gate, single-slot FIFO queue, worktree isolation, verify-then-PR, and
   the chat-reuse/handoff behavior once
   `dont-spawn-new-chat-ticket-per-execution-trigger` ships) applies to
   Bug exactly as it does to Task. No separate execution pathway.
5. **Link to Release via `relatesTo`** — reuses the existing cross-cutting
   mechanism `release` already has with `epic`/`story`/`task`, making
   "which bugs were found in Release X" a real, queryable relationship
   rather than a freeform string — even though Aion has no real
   versioned distribution yet, a Release ticket already stands alone as
   an internal milestone/checkpoint concept independent of actual app
   distribution.

## Conclusions reached

- **New `TicketType.bug`** added to the enum, alongside `epic | story |
  task | resource | page | chat | signal | release`.
- **`TicketTypeHierarchy`:** `bug` gets the same rank as `task` in the
  epic > story > task/bug chain (or an equivalent same-level slot —
  exact mechanism, see Open questions), so it can be parented by `story`
  or `epic` following the identical rules `task` already has, and can
  parent `chat` unconditionally like every other work type.
- **New fields on `Ticket`** (or a `bug`-specific value object, TBD):
  `severity` (a new enum, distinct from `TicketPriority`), `stepsToReproduce`
  (text), `expectedBehavior`/`actualBehavior` (text, likely two fields),
  and a `relatesTo` link to a `Release` ticket for affected
  version/environment — reusing the exact mechanism `release` already
  has with `epic`/`story`/`task`, now with `bug` as a fourth participant.
- **Coding-execution full parity:** every `ticket.type == TicketType.task`
  check site in `TicketsCubit` (design-review gate,
  `_interceptTaskExecutionTrigger`, single-slot queue, `_runCodingExecution`
  trigger, `getTicketById`'s execution-state computations, etc.) widens
  to accept `bug` too. `_assembleExecutionContext` folds the new fields
  (severity, repro steps, expected/actual, linked Release) into the
  model's starting context alongside title/description — no new
  execution pathway.

## Open questions

- Exact mechanism for `bug` sharing `task`'s rank in
  `TicketTypeHierarchy._rank` — whether it literally returns the same
  integer as `task` (making them fully interchangeable at that rank,
  including whatever same-rank restrictions exist) or gets its own
  distinct rank value that happens to sit at the same position in the
  parent-eligibility rules — left for `/propose`'s design.md to work out
  against `canParent`'s existing switch logic.
- Whether `severity` needs its own dedicated enum type
  (`domain/enums/ticket_severity.dart`, mirroring `TicketPriority`'s
  shape) or can reuse `TicketPriority`'s existing values under a
  different field name — not discussed, a natural `/propose` question.
- Whether `expectedBehavior`/`actualBehavior` are two separate fields or
  one combined freeform field — the question offered them as a pair but
  didn't force a single-vs-two split; left for design.md.
- How the create-ticket flow's type dropdown and any type-specific form
  fields (steps to reproduce, etc.) get exposed in `CreateTicketScreen` —
  presumably follows the same precedent `release`/`signal` set when they
  were added, not walked through this session.

## Architectural implications

- Extends the shipped type-compatibility matrix
  (`define-type-compatibility-matrix`) with an eighth `TicketType` value —
  the matrix's `canParent`/`_rank`/`isAlwaysRoot` logic all need a `bug`
  case added, following the same pattern `release`/`signal` set when
  they were added to an already-shipped matrix.
- Widens every coding-execution `TicketType.task` check site
  (`coding-execution-reliability-and-safety`,
  `task-to-coding-execution-trigger`) to a two-type set — the first time
  coding-execution's trigger surface covers more than one `TicketType`.
  Any idea currently in flight that also touches those check sites
  (`dont-spawn-new-chat-ticket-per-execution-trigger`,
  `board-execution-indicators-and-notifications`) should account for
  `bug` once this ships, or vice versa depending on ship order.
- Adds `bug` as a fourth `relatesTo` participant alongside
  `epic`/`story`/`task` on the `release` side of that relationship —
  `Release`'s existing "bundle loose ad hoc tasks with no epic" framing
  extends naturally to "bundle bugs found during this release" too.
- New `severity` field is deliberately kept distinct from the existing
  `TicketPriority` — two independent axes (impact vs. scheduling
  urgency) rather than overloading one field for both meanings.