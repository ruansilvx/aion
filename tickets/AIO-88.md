---
ticketId: AIO-88
type: story
status: done
priority: none
parentId: ca6e7e53-0dc1-4ffe-afbf-bcaeb56c1c6c
estimate: null
timeSpent: null
createdAt: 2026-09-02T21:17:20.135559
updatedAt: 2026-09-02T21:17:20.135559
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# 3. Estimation orchestrator

- [x] 3.1. Create
      `lib/features/tickets/presentation/cubit/ticket_estimation_suggester.dart`
      — `TicketEstimationSuggester` class per design.md §2.1–§2.2 in
      full: constructor, `suggest`/`regenerate`/`_run`, `_resolveModel`
      (mirroring `TicketsCubit._resolveModel`'s fallback chain),
      `_buildPrompt`, `_parseSuggestion`. Fully dartdoc'd per the class
      and method docs already drafted in design.md, plus file header.