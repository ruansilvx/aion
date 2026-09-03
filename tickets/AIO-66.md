---
ticketId: AIO-66
type: idea
status: backlog
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-07T00:00:00.000
updatedAt: 2026-08-17T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Ticket.copyWith silently drops deletedAt

## Key questions asked

1. The idea file's original conclusion was a settable copyWith param
   for deletedAt (like estimate/timeSpent). The code has since
   established a second precedent — sddStage/estimateRollup/
   timeSpentRollup/complexitySource/estimateSource/
   predictedExecutionTokensLow/High are all deliberately kept out of
   copyWith's params and just passed through unchanged, because each
   has its own dedicated repository write path. Which pattern should
   deletedAt follow?
2. Given the fix is a single unconditional line plus a doc-comment
   update, with no schema or behavior change, should this route to a
   full /propose cycle or land as a direct ad hoc fix?

## Summary of answers

1. Preserve-only, like sddStage/estimateRollup/complexitySource —
   don't add a copyWith param. deletedAt is written only by
   TicketRepository.trashTicket/restoreTicket (confirmed neither calls
   copyWith directly — they go through TicketDao.softDeleteByIds/
   restore methods), so it fits the "dedicated write path, must survive
   a plain content edit unchanged" pattern exactly, not the
   "user-settable via a generic edit" pattern estimate/timeSpent use.
2. Ad hoc fix: commit. Small, mechanical, single-file, no behavior
   change beyond closing the latent bug — doesn't warrant a
   proposal.md/design.md/tasks.md cycle per project.md's "Outside an
   OpenSpec cycle" rule for small bug fixes.

## Conclusions reached

Fix Ticket.copyWith (aion/lib/features/tickets/domain/entities/ticket.dart)
to pass `deletedAt: deletedAt` through unconditionally in the
reconstructed Ticket(...), with no new settable parameter — the same
treatment already given to sddStage/estimateRollup/timeSpentRollup/
complexitySource/estimateSource/predictedExecutionTokensLow/High.
Update the copyWith doc comment to add deletedAt to that preserved-field
list. Land as a standalone ad hoc `fix:` commit, not an OpenSpec change.

## Open questions

None remaining — this is ready to fix directly.

## Architectural implications

Reinforces the existing Ticket.copyWith convention (already documented
in the entity's own doc comments, citing this idea file as precedent):
any field written only through a dedicated repository method must be
passed through copyWith unconditionally rather than exposed as a
settable param, so a generic content edit can never silently clobber
it. No related_specs/related_ideas — this is a self-contained
correctness fix with no ripple into other areas.