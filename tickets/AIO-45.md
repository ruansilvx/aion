---
ticketId: AIO-45
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-13T00:00:00.000
updatedAt: 2026-08-19T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Page-nesting depth limit

## Key questions asked

1. Unbounded page nesting today — what's actually prompting a cap: a real problem hit in practice, or just closing the open question the shipped Documentation section left dangling?
2. `DocumentationTreeItem` renders depth-based indent in the sidebar tree. With no cap, deep nesting could push indentation off narrow/mobile screens. Does that risk alone justify a hard cap, or is it acceptable to leave unbounded and handle indent visually?

## Summary of answers

1. No concrete incident or complaint — this is purely closing the open question `notion-obsidian-like-documentation-section` left unresolved at ship time.
2. Leave unbounded (recommended, and confirmed) — the indent-overflow risk should be handled visually, not by blocking the data model with an arbitrary depth cap.

## Conclusions reached

No hard nesting-depth limit on the data model, `TicketTypeHierarchy.canParent`, or any `TicketsCubit` invariant — `page`-under-`page` nesting stays unbounded, since a personal docs vault is unlikely to realistically nest deep enough for a cap to matter, and an artificial limit would only exist to protect UI rendering, not data integrity.

Instead, address the actual risk — sidebar indent overflow on narrow/mobile screens — at the UI layer: clamp `DocumentationTreeItem`'s rendered indent in pixels past some depth (e.g. flatten further indent increments, or let the row scroll horizontally) so nesting can go arbitrarily deep without breaking layout.

## Open questions

- Exact indent-clamping mechanics (max depth before clamping kicks in, horizontal scroll vs. flattened indent) — left to `/propose`.
- Whether `chat`'s existing `TicketsCubit`-level depth cap (a different invariant, for conversation-branching reasons) sets any useful precedent here — probably not, but worth a quick check during `/propose`.

## Architectural implications

- No change to `TicketTypeHierarchy.canParent` or the `page`/`resource` data model.
- `DocumentationTreeItem` (`presentation/widgets/documentation_tree_item.dart`) needs its indent calculation updated to clamp rather than grow unbounded with depth.
- Closes out the "no page-nesting depth limit is enforced" known gap carried forward from [[notion-obsidian-like-documentation-section]].