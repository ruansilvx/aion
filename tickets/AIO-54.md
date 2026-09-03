---
ticketId: AIO-54
type: idea
status: backlog
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-09-01T00:00:00.000
updatedAt: 2026-09-01T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Promote Idea to Story

Widen TicketsCubit.promoteIdea to support a third target type: Story. Today promoteIdea's targetType parameter only accepts epic or bug (tickets.md:2168-2171) — it was renamed/widened from the original promoteSignalToEpic to add Bug support, but Story was never part of that widening. So an idea that's really Story-shaped and belongs under an existing, not-yet-archived Epic has no dedicated promotion path at all: the idea detail screen's "Link to existing epic/bug" / "Create new epic/bug" rows (tickets.md:5354-5368) are hard-scoped to just those two types.

Today's only workaround is fully manual: create a new story ticket by hand, parent it under the existing Epic via TicketParentPicker/reparent, copy the idea's title/description over yourself, then either trash the original idea ticket or leave it linked via a manually-drawn relatesTo link — none of which promoteIdea does for you, since it never ran.

This isn't listed in tickets.md's existing Known gaps section (checked) — it's an undocumented gap, not a deliberately deferred one.

Idea: add targetType: story as a valid promoteIdea option. Unlike epic/bug (which can be created freestanding), a new Story ticket structurally requires a parent Epic (per the ticket-type hierarchy's parent/child compatibility rules) — so this necessarily also requires an existingTicketId (the target Epic to parent under), likely making "Create new story" always route through the same "pick a target" picker flow "Link to existing epic/bug" already uses, rather than getting its own no-picker "Create new" shortcut the way epic/bug currently do. Candidate shapes to weigh during /brainstorm or /propose:
- Whether Story promotion should require picking an existing Epic every time (no freestanding-Story creation path at all, consistent with the type hierarchy), or whether some flow should let you create a brand new Epic AND Story together in one promote action.
- Whether Ticket.suggestedType (currently epic | bug only, per the Inbox brain-dump classifier) should ever suggest story, and if so what signal the classifier would use to prefer an existing Epic over a new one — likely out of scope for a first pass given the classifier has no visibility into which Epics are still open/unarchived today.
- UI: does the idea detail screen grow a third promote row ("Link to existing story" doesn't quite make sense — more likely "Add as story under existing epic"), or does "Link to existing epic" gain a modifier/follow-up step ("...as a new story under it" vs "...linked via relatesTo")?