---
ticketId: AIO-84
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
# 2.4. Edit `lib/features/tickets/data/repositories/drift_ticket_repository.dart`

— implement `applyEstimationSuggestion` (via
`TicketDao.updateFields`, no `updatedAt`); update `updateTicket`'s
and `createTicket`'s companion-building code to stamp
`complexitySource`/`estimateSource` per design.md §3.2; update
`_toEntity` to parse both new nullable enum columns via
`_parseNullableEnum(TicketEstimationSource.values, ...)`.