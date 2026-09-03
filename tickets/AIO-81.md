---
ticketId: AIO-81
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
# 2.1. Edit `lib/features/tickets/domain/repositories/ticket_repository.dart`

— add `applyEstimationSuggestion(id, {complexity, estimate})` per
design.md §3.1, dartdoc'd; update `updateTicket`'s dartdoc to
document the new source-stamping side effect.