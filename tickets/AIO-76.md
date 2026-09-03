---
ticketId: AIO-76
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
# 1. Domain layer

- [x] 1.1. Create `lib/features/tickets/domain/enums/ticket_estimation_source.dart`
      — `TicketEstimationSource` enum (`aiSuggested`,
      `aiSuggestedLowConfidence`, `manual`), fully dartdoc'd per design.md
      §1.1, plus the file header comment.
- [x] 1.2. Create `lib/features/tickets/domain/utils/embedding_similarity.dart`
      — top-level `cosineSimilarity(Uint8List a, Uint8List b)`, body moved
      verbatim from `TicketDocumentSearchService._cosineSimilarity` (see
      1.6 for the corresponding removal), dartdoc'd, plus file header.
- [x] 1.3. Edit `lib/features/tickets/domain/entities/ticket.dart` — add
      `complexitySource`/`estimateSource` fields (constructor, `props`),
      dartdoc'd per design.md §1.2; update `complexity`'s/`estimate`'s own
      dartdocs with a one-line pointer to their companion source field.
      `copyWith` is NOT touched — confirm it still excludes both new
      fields.