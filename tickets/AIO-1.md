---
ticketId: AIO-1
type: task
status: inProgress
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-23T00:43:02.315
updatedAt: 2026-07-23T01:25:06.842
---
# Fix overflow menu missing depth cue in Obsidian dark theme

TicketOverflowMenu lib/features/tickets/presentation/widgets/ticket_overflow_menu.dart renders its overlay container with AionShadows.cardc, t.isDark, which intentionally returns an empty shadow list in Obsidian dark theme in favor of a border-based elevation cue instead. The container already sets border: Border.allcolor: c.borderStrong, width: 1. Known gap recorded in aion-arch/specs/tickets.md's Known gaps section: