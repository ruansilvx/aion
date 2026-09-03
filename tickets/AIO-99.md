---
ticketId: AIO-99
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
# 7. Tests

- [x] 7.1. `test/features/tickets/domain/utils/embedding_similarity_test.dart`
      — unit tests for `cosineSimilarity` (moved/adapted from
      `TicketDocumentSearchService`'s existing coverage of the same
      logic, if any exists there today).
- [x] 7.2. `test/features/tickets/presentation/cubit/ticket_estimation_suggester_test.dart`
      — mocktail-based unit tests per design.md §7: both-fields-locked
      no-op, cold-start → `aiSuggestedLowConfidence`, comparable-tickets
      path → `aiSuggested`, malformed/missing response line skips that
      field only, `AgentErrorEvent`/thrown exception swallowed, `regenerate`
      bypasses a `manual` lock for only the forced field and leaves the
      other field's source untouched.
- [x] 7.3. Extend `test/features/tickets/data/repositories/drift_ticket_repository_test.dart`
      (or wherever its existing suite lives) — `applyEstimationSuggestion`
      writes the right column(s) without touching `updatedAt`;
      `updateTicket`/`createTicket` stamp `manual` correctly, including
      the clear-to-`null` case when a field is unset.
- [x] 7.4. Extend `test/core/database/app_database_test.dart` (or
      equivalent migration test suite) — a schema-9 fixture with
      pre-existing `complexity`/`estimate` values upgrades to schema 10
      with both sources correctly backfilled to `'manual'`; a row with
      neither field set gets `null`/`null`. (No `test/core/database/`
      suite exists — this app's migration coverage lives in
      `drift_ticket_repository_test.dart`'s `'schema migration (v1 ->
      current)'` group, same "or equivalent" precedent v7→v8/v8→v9
      already established there; the v9→v10 test was added alongside
      7.3.)
- [x] 7.5. Extend `test/features/tickets/presentation/cubit/tickets_cubit_test.dart`
      — `createTicket`/`updateTicket` invoke the estimation suggester
      under the documented conditions; `regenerateComplexitySuggestion`/
      `regenerateEstimateSuggestion` no-op on an unset field and emit
      `TicketDetailLoaded` on completion (including the silent-failure
      case).
- [x] 7.6. Extend `test/features/tickets/presentation/widgets/ticket_metadata_section_test.dart`
      (or equivalent widget test suite) — badge renders for
      `aiSuggested`/`aiSuggestedLowConfidence`, Regenerate button renders
      only for `manual`, tapping it invokes the right Cubit method.