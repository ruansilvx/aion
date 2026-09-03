---
ticketId: AIO-21
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
# Create, edit and delete pages

## Key questions asked

1. Given pages already have generic create/edit/delete via shared ticket CRUD infrastructure, what's actually missing?
2. Do you want a Markdown-rendering editor (simpler, reuses existing sync infra) or a true block-based editor with draggable blocks (bigger scope, new content data model)?
3. Should this apply just to `page` tickets, or also `resource` tickets / other ticket types' description fields?
4. For the editing interaction: toggle between raw/rendered, or live split view?

## Summary of answers

1. The actual want is rich-text/block-style editing for page *content*, not the metadata CRUD (which already works).
2. Markdown-rendering editor — not a draggable block editor. May revisit block-style editing in the future.
3. Page tickets only. Resource tickets are meant to stay file-based (audio, images, spreadsheets, PDFs, etc.) — that's the separate "upload and visualize files for resource tickets" idea's scope, not this one's.
4. Toggle (edit/view) on smaller/mobile screens; live split view (raw + rendered side-by-side) on bigger screens.

## Conclusions reached

Build a Markdown-rendering content editor scoped to `page` tickets only, replacing the current plain `InlineEditableField<T>` description field for that type. Content remains a plain Markdown string — no new data model — so it keeps working with the existing `TicketMarkdownSerializer`/`TicketMarkdownReconciler` file-sync pipeline untouched. Responsive UX: toggle-based edit/view on narrow screens, live split view (raw + rendered) on wide screens. A true draggable block-based editor is explicitly deferred, not ruled out.

## Open questions

- Which Markdown rendering package/approach to use (a `/propose` implementation detail, not an architectural fork).
- Exact breakpoint for switching between toggle and split-view layouts.
- Whether toolbar/formatting shortcuts (bold, heading, list) are in scope for v1 or a fast-follow.

## Architectural implications

- No change to the `Ticket` entity or Markdown file format — content stays a string field, so `TicketMarkdownSerializer`/`TicketMarkdownReconciler` (see `related_specs: tickets.md`) need no changes.
- Only affects `TicketDetailScreen`'s content-editing widget for `page`-type tickets; `resource` tickets keep their current (file-based) treatment, to be addressed separately by [[upload-and-visualize-files-for-resource-tickets]].
- Builds directly on top of the already-shipped [[notion-obsidian-like-documentation-section]] work (Documentation section, page/resource tree, sub-page nesting) — this idea only touches the content-editing widget, not the surrounding page/document structure.