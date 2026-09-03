---
ticketId: AIO-89
type: task
status: done
priority: none
parentId: 51dc9d0f-c77f-4111-98f0-847ce4212cea
estimate: null
timeSpent: null
createdAt: 2026-09-02T21:17:20.135559
updatedAt: 2026-09-02T21:17:20.135559
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# 3.1. Create

`lib/features/tickets/presentation/cubit/ticket_estimation_suggester.dart`
— `TicketEstimationSuggester` class per design.md §2.1–§2.2 in
full: constructor, `suggest`/`regenerate`/`_run`, `_resolveModel`
(mirroring `TicketsCubit._resolveModel`'s fallback chain),
`_buildPrompt`, `_parseSuggestion`. Fully dartdoc'd per the class
and method docs already drafted in design.md, plus file header.