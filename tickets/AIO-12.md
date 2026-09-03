---
ticketId: AIO-12
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-24T00:00:00.000
updatedAt: 2026-07-30T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Board visual indication of task ordering (blocks/blockedBy)

## Key questions asked

1. Since work tickets have no link-creation UI at all today, how should a
   user actually establish that Task B is blocked by Task A?
2. Where should agent-driven auto-linking of blocks/blockedBy actually
   happen, given SDD-stage chats are zero-tool-access today?
3. Should the new tool-enabled decomposition capability be the existing
   "proposed" stage gaining tools, or a brand-new stage inserted into the
   sequence?
4. How should the Board actually treat a blocked Task — visual only, or
   does it also gate the status transition itself?

## Summary of answers

1. **Extend `TicketLinkPicker` to work tickets, for manual links** — plus
   the agent should be able to automatically link tickets, not manual
   linking alone.
2. **A new tool-enabled decomposition step** — not a general "any
   ticket-creating chat" capability. Scoped specifically to Epic/Story
   decomposition into child Stories/Tasks, since that's the concrete case
   where ordering dependencies are known at creation time.
3. **The existing "proposed" stage gains tools** — no new stage inserted
   into `exploring → proposed → designBrief → designSync → verifying →
   archived`. `proposed`'s chat gets a new ticket-creation-and-linking
   tool tier so it materializes what it currently only describes in
   text.
4. **Visual only** — a "blocked" badge/icon, informational, same spirit
   as the existing priority/status badges. No hard gate on dragging a
   blocked Task to `inProgress`; Aion shows the dependency, doesn't
   enforce it.

## Conclusions reached

Three pieces, all needed together for ordering to actually work
end-to-end:

- **Manual linking:** generalize the resource-only `TicketLinkPicker`/
  `LinkedTicketsSection` to also render on `epic`/`story`/`task` tickets,
  with a link-type selector (`blocks`/`blockedBy`/`relatesTo`/
  `duplicates`) instead of the current hardcoded `TicketLinkType.
  relatesTo` call.
- **Agentic linking:** the `proposed` SDD-stage chat gains a new tool
  tier — ticket-creation-and-linking only, distinct from coding
  execution's full file/git/bash tier and `designSync`'s read-only tier —
  so decomposing an Epic/Story into child Stories/Tasks directly creates
  those tickets and establishes `blocks`/`blockedBy` between them, rather
  than requiring the human to manually create each child ticket after
  reading a text proposal.
- **Board visualization:** a "blocked" badge/icon on `TicketBoardCard`
  whenever a work ticket has an unresolved `blockedBy` link (its blocker
  isn't `done`) — informational only, no enforcement on drag/status
  change.

## Open questions

- Exact new tool tier's shape (what tools it exposes — presumably a
  narrow "create ticket" / "link tickets" tool pair, nothing broader) —
  left for `/propose`'s design.md, following the precedent
  `design-gate-for-ticket-driven-sdd-workflow` set for `designSync`'s
  read-only tier.
- Whether the `proposed` stage's existing text-only behavior (for a
  Story, or an Epic/Story that doesn't need further decomposition) stays
  as a fallback when there's nothing to decompose, or the tool-enabled
  path always runs regardless — not walked through this session.
- Exact visual treatment for the "blocked" badge (icon, tooltip content
  listing which ticket(s) block it) — a `design-brief`/`design-sync`
  question, not architectural.
- Whether `duplicates`/`duplicatedBy` links get any UI treatment as part
  of generalizing `TicketLinkPicker`, or only `blocks`/`blockedBy` are in
  scope for this change — the link-type selector naturally exposes all
  four, but visual/board treatment was only discussed for
  `blocks`/`blockedBy`.

## Architectural implications

- `TicketLinkType.blocks`/`blockedBy` go from unused enum values to a
  real, user- and agent-facing relationship for the first time.
- Adds a third tool-access tier alongside coding-execution's full tier
  and `designSync`'s read-only tier (`design-gate-for-ticket-driven-sdd-
  workflow`) — `proposed`'s new ticket-creation-and-linking tier. Tool
  tiers are becoming a real, growing axis independent of `SddStage`
  position, worth keeping consistent as more stages potentially need
  their own scoped access.
- `TicketLinkPicker`/`LinkedTicketsSection` generalize beyond
  `resource`-only — the "Linked Tickets" UI becomes a first-class part of
  `TicketDetailScreen` for every ticket type, not just resource.
- The Board (`TicketBoardCard`) gains a second new state-driven badge
  alongside `board-execution-indicators-and-notifications`' execution
  indicators — worth designing both in the same visual pass so cards
  don't become cluttered with unrelated badge styles.
- Depends on `sdd-workflow-in-ticket-system`'s existing Epic→Story→Task
  decomposition flow as the integration point for the new agentic-linking
  capability — this idea doesn't change *when* decomposition happens,
  only what the `proposed` stage chat can now directly do once it does.