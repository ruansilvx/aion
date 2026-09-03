---
ticketId: AIO-97
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
# 6. Localization

- [x] 6.1. Edit `lib/l10n/app_en.arb` — add `aiSuggestedBadge`,
      `aiSuggestedLowConfidenceBadge`, `ticketDetailRegenerateComplexity`,
      `ticketDetailRegenerateEstimate` keys per design.md §6, placed
      alongside the existing `ticketDetail*`/`ticketComplexity*` keys.
      Run whatever the project's existing l10n codegen step is (matching
      how prior string additions in this file have been picked up) so the
      generated accessors exist for 5.2/3.1 to reference.