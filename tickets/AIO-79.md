---
ticketId: AIO-79
type: task
status: done
priority: none
parentId: d1840bd8-d38a-435d-91d2-72d9c3870406
estimate: null
timeSpent: null
createdAt: 2026-09-02T21:17:20.135559
updatedAt: 2026-09-02T21:17:20.135559
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# 1.3. Edit `lib/features/tickets/domain/entities/ticket.dart` — add

`complexitySource`/`estimateSource` fields (constructor, `props`),
dartdoc'd per design.md §1.2; update `complexity`'s/`estimate`'s own
dartdocs with a one-line pointer to their companion source field.
`copyWith` is NOT touched — confirm it still excludes both new
fields.