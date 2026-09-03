---
ticketId: AIO-43
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-18T00:00:00.000
updatedAt: 2026-07-19T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Notion/Obsidian-like documentation section

## Key questions asked

1. Is this a read-only navigator, or the primary place resources/pages get created and edited?
2. Should resource/page tickets be removed from the board now that they have a dedicated home, or shown in both places?
3. Should pages/resources nest under each other (Notion-style sub-pages) now that they're leaving the board's work-item hierarchy?
4. Does `chat` (the third leaf type) move into this section too, or stay a board-ticket attachment?
5. Are backlinks and full-text search core to the MVP, or deferred enhancements?
6. Should search reuse Aion's existing embedding-based search infra, or a simpler literal text match?
7. What happens to existing resource/page tickets' current `parentId` (work-item) relationships when this ships?

## Summary of answers

1. Primary place for resources and pages — not just a browser. Motivated by wanting to visualize/navigate documentation without hunting ticket-by-ticket, plus a general "knowledge vault" want.
2. Removed from the board entirely — this section is their home now. They remain linkable to board tickets, and that link displays on both sides (ticket shows linked docs, doc shows linked tickets).
3. Nested, Notion-style: pages can contain sub-pages. Resources remain leaves (no children).
4. Chat stays a board-ticket attachment only — not part of this section.
5. Both full-text search and backlinks are core to the MVP, not deferred.
6. Reuse the existing embedding-based search infra, for consistency with the rest of the app.
7. Auto-migrate: existing parentId (work-item) relationships convert into the new linked-ticket relationship automatically. Nothing is left orphaned.

## Conclusions reached

Build a new top-level documentation section as the primary home for `resource` and `page` tickets, replacing their presence on the board:

- **Removed from board:** resource/page tickets no longer appear in the Jira-like board or its type-compatibility hierarchy as board-parented leaves.
- **New hierarchy:** pages can nest sub-pages (Notion-style); resources stay leaf-only, nestable under pages but without children of their own.
- **Cross-linking preserved:** a page/resource can still link to one or more board tickets; the relationship displays on both the doc (linked tickets) and the ticket (linked docs) — this reuses/extends the existing ticket-link model (see `ticket-link-count-excludes-trashed`).
- **Chat unaffected:** stays a board-ticket-only attachment, not part of this section.
- **Search & backlinks are MVP, not follow-up:** full-text search reuses the existing embedding infrastructure; backlinks ("what links to this page") ship in the same pass.
- **Migration:** on ship, existing resource/page `parentId` values (currently pointing at an epic/story/task) auto-convert into the new linked-ticket relationship rather than leaving those docs orphaned or requiring manual re-linking.

## Open questions

- Nesting depth: is there a practical cap on page-nesting depth, or is it unbounded? Not discussed — worth resolving during `/propose` since it affects sidebar-tree/breadcrumb UI design.
- How this interacts with the known gap "no dedicated UI for browsing, creating, or editing individual pages" (`aion-arch/specs/tickets.md`) — this idea appears to directly resolve that gap; `/propose` should confirm and reference it explicitly.
- Relationship to the "Create, edit and delete pages" idea ([[create-edit-and-delete-pages]]) — that idea's raw one-line scope likely gets absorbed into this change rather than staying separate; worth confirming at `/propose` time.

## Architectural implications

- **Type-compatibility matrix change:** `TicketTypeHierarchy.canParent` currently treats resource/page/chat as leaf attachments under any work type. This idea splits that: `page` gains the ability to parent other `page`/`resource` tickets, while `chat` keeps the current leaf-only rule. This is a structural change to an already-shipped rule (see [[define-type-compatibility-matrix]]).
- **Ticket linking model reuse:** the bidirectional "linked ticket" relationship should extend the existing ticket-link infrastructure rather than introduce a parallel one.
- **Search infra reuse:** ties this idea to the existing embedding/drift search work (see [[storage-model-per-project-scoping]]) — no new search stack, just a new surface querying the same index.
- **Migration step required:** `/propose` needs an explicit data-migration task converting existing resource/page `parentId` values into linked-ticket rows, run once at upgrade time.