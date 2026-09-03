---
ticketId: AIO-68
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-06T00:00:00.000
updatedAt: 2026-08-06T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Ticket link management UI (view, edit, delete ticket_links)

## Key questions asked

1. What's actually biting you day-to-day right now — "I created a link
   by mistake and can't remove it," "I can't tell what two tickets are
   linked as without digging," or both?
2. Where should this live — inline on the ticket detail screen, a
   separate global "all links" browser screen, or a third shape?
3. (Detour) How does Jira handle this?
4. Given Jira's inline-only precedent, is inline-only sufficient for
   Aion, or is there a real cross-project auditing need Jira's JQL
   fallback wouldn't have here?
5. Do you need true in-place editing of an existing link's type, or is
   delete-and-recreate via the existing TicketLinkPicker good enough?
6. Pros/cons of a true atomic `updateLinkType` repository method vs.
   delete+recreate under the hood?

## Summary of answers

- Both the "can't remove a mistaken/stale link" and "can't see what a
  ticket is linked as beyond a count" pains are real, equally.
- Jira keeps link management entirely inline (a "Linked issues" section
  per issue, delete icon per row) with no dedicated global link-browser
  screen — cross-project auditing falls back to JQL search, which Aion
  has no equivalent of, but the developer confirmed no global-screen
  need exists here regardless.
- In-place type editing is wanted, not just delete+recreate.
- Weighing atomic update (extra Cubit-side invariant work: recompute
  the inverse blocks/blockedBy side, re-validate the new type against
  TicketTypeHierarchy) against delete+recreate (reuses existing code,
  but risks silently losing the link entirely if the recreate half
  fails, and ripples as two separate events through BlockedBadge/git
  projection instead of one) — developer chose the atomic update,
  accepting the extra Cubit work to avoid the partial-failure data-loss
  risk and the double-event ripple.

## Conclusions reached

Extend the existing inline "Linked Tickets" section on the ticket
detail screen (next to where `TicketLinkPicker` already handles
creation) with:

1. A delete/remove action per link row (currently link deletion has no
   UI path at all).
2. True in-place link-type editing via a new atomic
   `TicketLinkRepository.updateLinkType`, with the Cubit (not the
   repository) owning the invariant logic — recalculating the inverse
   `blocks`/`blockedBy` side and re-validating the new type against
   `TicketTypeHierarchy` for that ticket-type pair, per this project's
   established Cubit-domain-logic convention.

No separate global "browse all links" screen — inline-only, matching
Jira's own precedent and confirmed sufficient by the developer.

## Open questions

- Delete-confirmation UX (a confirm dialog mirroring existing
  destructive-action patterns elsewhere in the app, e.g. trash) was not
  explicitly nailed down — left as an implementation detail for
  `/propose`/`/apply` rather than a direction-level decision.
- "AI-reviewed manual changes" — the developer flagged that edits to
  link data will eventually need to interact with some AI-review
  mechanism discussed previously elsewhere in the project. Not resolved
  here; this idea's scope is the UI/repository/Cubit mechanics only.
  Whoever picks this up should check whether that mechanism has since
  been scoped in another idea/spec before `/propose`.

## Architectural implications

- Adds a real `update` path to `TicketLinkRepository` (today it's
  create/read/delete-shaped per `board-task-ordering-indication`'s
  delivery) — the first non-create/delete mutation on `ticket_links`.
- Reinforces, rather than conflicts with, the project's existing
  Cubit-owns-domain-logic convention — the inverse-pair recalculation
  and type-compatibility re-validation both belong in `TicketsCubit`
  (or a link-specific Cubit slice), not pushed down to the repository.
- Related but explicitly out of scope: an Obsidian-style visual graph
  view of ticket relationships was raised mid-session as a genuinely
  separate, larger feature — worth its own future `/capture` or
  `/brainstorm`, not folded into this change.