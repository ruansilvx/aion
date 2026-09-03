---
ticketId: AIO-80
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
# 2. Repository interface & data layer

- [x] 2.1. Edit `lib/features/tickets/domain/repositories/ticket_repository.dart`
      — add `applyEstimationSuggestion(id, {complexity, estimate})` per
      design.md §3.1, dartdoc'd; update `updateTicket`'s dartdoc to
      document the new source-stamping side effect.
- [x] 2.2. Edit `lib/features/tickets/data/models/ticket_model.dart` —
      add `complexitySource`/`estimateSource` `TextColumn`s to
      `TicketsTable` per design.md §3.3, dartdoc'd.
- [x] 2.3. Edit `lib/core/database/app_database.dart` — bump
      `schemaVersion` to `10`, add the `if (from < 10)` migration block
      (add both columns, backfill both sources to `'manual'` for
      already-sized rows) per design.md §3.4. Update the class-level
      dartdoc comment block that documents each schema version's changes
      (the one referenced near "Version 9 adds...") with a "Version 10
      adds..." line.
- [x] 2.4. Edit `lib/features/tickets/data/repositories/drift_ticket_repository.dart`
      — implement `applyEstimationSuggestion` (via
      `TicketDao.updateFields`, no `updatedAt`); update `updateTicket`'s
      and `createTicket`'s companion-building code to stamp
      `complexitySource`/`estimateSource` per design.md §3.2; update
      `_toEntity` to parse both new nullable enum columns via
      `_parseNullableEnum(TicketEstimationSource.values, ...)`.
- [x] 2.5. Edit `lib/features/tickets/data/services/ticket_document_search_service.dart`
      — remove the private `_cosineSimilarity` method, call the new
      shared `cosineSimilarity` from `embedding_similarity.dart` instead;
      update the file's imports.
- [x] 2.6. Edit `lib/features/tickets/presentation/cubit/ticket_rollup_recomputer.dart`
      — update `_withRollup`'s full `Ticket(...)` reconstruction to pass
      through `complexitySource: ticket.complexitySource, estimateSource:
      ticket.estimateSource,` (mechanical, per design.md §2.3).
- [x] 2.7. Grep the rest of the app repo for any other place that
      constructs a `Ticket(...)` naming every field explicitly (test
      fixtures/mocks aside — see §5) and add the same two pass-through
      lines wherever a real (non-test) production code path does this.