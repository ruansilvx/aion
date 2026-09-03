---
ticketId: AIO-96
type: task
status: done
priority: none
parentId: 8466da55-7941-475f-8650-269477fafbe0
estimate: null
timeSpent: null
createdAt: 2026-09-02T21:17:20.135559
updatedAt: 2026-09-02T21:17:20.135559
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# 5.2. Edit `lib/features/tickets/presentation/widgets/ticket_metadata_section.dart`

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