---
ticketId: AIO-90
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
# 4. `TicketsCubit` wiring

- [x] 4.1. Edit `lib/features/tickets/presentation/cubit/tickets_cubit.dart`
      — construct `_estimationSuggester` in the constructor body per
      design.md §4.1 (add the `late final TicketEstimationSuggester
      _estimationSuggester;` field with a dartdoc, wired to the same
      `embeddingProvider`/`providerRegistry`/`modelRoutingRepository`
      params already accepted).
- [x] 4.2. Same file — add the `unawaited(_estimationSuggester.suggest(...))`
      call to `createTicket` (right after the existing
      `_triggerEmbeddingRegen` call) and to `updateTicket` (inside the
      existing title/description-changed `if` block) per design.md §4.2.
      Update both methods' dartdocs to mention the new side effect,
      matching how they already document `_triggerEmbeddingRegen`.
- [x] 4.3. Same file — add
      `regenerateComplexitySuggestion(Ticket ticket)` and
      `regenerateEstimateSuggestion(Ticket ticket)` public methods per
      design.md §4.3, fully dartdoc'd.