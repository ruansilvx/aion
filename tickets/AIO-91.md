---
ticketId: AIO-91
type: task
status: done
priority: none
parentId: a4c0cd4d-651a-40cc-980b-f97ef5445d4d
estimate: null
timeSpent: null
createdAt: 2026-09-02T21:17:20.135559
updatedAt: 2026-09-02T21:17:20.135559
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# 4.1. Edit `lib/features/tickets/presentation/cubit/tickets_cubit.dart`

— construct `_estimationSuggester` in the constructor body per
design.md §4.1 (add the `late final TicketEstimationSuggester
_estimationSuggester;` field with a dartdoc, wired to the same
`embeddingProvider`/`providerRegistry`/`modelRoutingRepository`
params already accepted).