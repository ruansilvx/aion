---
ticketId: AIO-86
type: task
status: done
priority: none
parentId: 730b86dd-9df8-495f-a8a8-4e9172a250a9
estimate: null
timeSpent: null
createdAt: 2026-09-02T21:17:20.135559
updatedAt: 2026-09-02T21:17:20.135559
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# 2.6. Edit `lib/features/tickets/presentation/cubit/ticket_rollup_recomputer.dart`

— update `_withRollup`'s full `Ticket(...)` reconstruction to pass
through `complexitySource: ticket.complexitySource, estimateSource:
ticket.estimateSource,` (mechanical, per design.md §2.3).