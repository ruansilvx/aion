---
ticketId: AIO-69
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-10T00:00:00.000
updatedAt: 2026-08-11T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Ticket sort control and board as default view

## Key questions asked

1. What's actually motivating this — one specific missing sort field, or a general multi-field sort control from the start?
2. Which fields need to be selectable in v1 — a curated subset, or everything available on `Ticket` (priority/status/type/createdAt/updatedAt)?
3. When a search query is active (currently ordered by BM25 relevance) and a manual sort field is also selected, which wins — what's the usual convention for this?
4. Should the chosen sort persist per-project like the existing filters, or reset each time the ticket list opens?
5. Does the sort control apply only to the main ticket list, or also to Board's column ordering and/or the Trash screen?
6. Is this a single active sort key at a time, or a stacked/compound sort (primary + secondary keys) — what's the usual convention?
7. Final confirmation: persist this idea now, with Trash explicitly in scope.

## Summary of answers

- General multi-field control, not a single missing field.
- All of priority, status, type, createdAt, updatedAt should be selectable.
- Adopted the Linear/GitHub-Issues convention: "Relevance" is just another selectable sort option, offered and defaulted-to only while a search query is active — it isn't a separate mode. Picking any other field explicitly overrides it and stays sticky (even while a query remains active) until the user changes it back.
- Persists per-project, using the same mechanism as the existing status/type/priority filters (`SharedPrefsTicketListFilterRepository`-style).
- Applies everywhere ticket ordering matters: the ticket list, Board, and Trash.
- Board becomes the default view on open — a separate decision from sorting, but explicitly bundled into this same change rather than split into its own cycle ("not worth wasting a cycle on it").
- Single active `{field, direction}` sort key, not a compound/stacked sort — matches the simplest-useful convention for this class of tool (Linear/GitHub Issues keep it single-key; multi-level sort is mostly a spreadsheet-tool pattern like Notion/Airtable databases, more machinery than this needs).

## Conclusions reached

Ship a single-active-key sort control (`{field, direction}`) with selectable fields = priority, status, type, createdAt, updatedAt, plus "Relevance" (query-active only, default but explicitly overridable and sticky once overridden). Applied uniformly across List, Board, and Trash. Persisted per-project the same way the existing filters are. Bundled with a second decision from the same session: Board becomes the default view on open. Next step is `/propose` to turn this into a formal OpenSpec change.

## Open questions

- Exact default direction per field (e.g. is "Priority" first-shown high→low or low→high?) — left for `/propose` to settle with sensible per-field defaults.
- Whether Board already has any manual drag-reordering within a column that a shared sort setting would need to coexist with or override — needs checking against Board's current spec/behavior during `/propose`.
- Exact UI placement of the sort control — presumably alongside the existing `TicketFilterPopover`/`AppFilterChip` filter UI, but that's an implementation detail for `/propose`, not settled here.

## Architectural implications

- Extends the existing per-project filter-persistence pattern (`SharedPrefsTicketListFilterRepository`) to also store a `{field, direction}` sort selection — likely the same repository or a sibling one, keyed the same way (per-project).
- Touches `TicketsCubit` (new sort state alongside the existing filter-toggle state), `TicketsListScreen`, the Board screen, and the Trash screen's ticket ordering.
- Replaces the current hardcoded "relevance-if-querying, else createdAt-desc" default logic (`tickets.md`'s known-gaps bullet on this) with "Relevance" as a first-class, explicit sort-option value rather than an implicit special case.
- Bundles a navigation-default change (Board as default view) that is logically independent of sorting — worth calling out explicitly in the eventual `proposal.md` so reviewers don't miss that it's two decisions riding in one change.