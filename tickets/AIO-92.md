---
ticketId: AIO-92
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
# 4.2. Same file — add the `unawaited(_estimationSuggester.suggest(...))`

call to `createTicket` (right after the existing
`_triggerEmbeddingRegen` call) and to `updateTicket` (inside the
existing title/description-changed `if` block) per design.md §4.2.
Update both methods' dartdocs to mention the new side effect,
matching how they already document `_triggerEmbeddingRegen`.