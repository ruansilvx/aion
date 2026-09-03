---
ticketId: AIO-94
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
# 5. Design system

- [x] 5.1. Create `lib/design_system/molecules/ai_suggestion_badge.dart`
      — `AiSuggestionBadge` widget per design.md §0 Foundations for this
      feature & §1 AiSuggestionBadge (plain + low-confidence variants),
      dartdoc'd, file header. Visual details (icon, exact colors/
      padding) follow the Claude Design export in `design.md`'s
      design-gate section once `/design-sync` has run — this task
      implements whatever that export specifies; do not invent visuals
      ahead of it.
- [x] 5.2. Edit `lib/features/tickets/presentation/widgets/ticket_metadata_section.dart`
      — wire `AiSuggestionBadge` + the Regenerate icon button into both
      the Complexity `SelectionMenu` row and the Estimate
      `InlineEditableField` row per design.md §2 RegenerateButton & §3
      Composed row states — TicketMetadataSection, reading
      `ticket.complexitySource`/`estimateSource` and calling
      `TicketsCubit.regenerateComplexitySuggestion`/
      `regenerateEstimateSuggestion`. Update the file's own top-level
      dartdoc (currently listing "priority/complexity/title/type/status
      row, parent picker, estimate/time-spent fields...") to mention the
      new badge/regenerate affordances.