---
ticketId: AIO-24
type: idea
status: backlog
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-19T00:00:00.000
updatedAt: 2026-07-19T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Dedicated page screens as a separate feature module

## Key questions asked

1. What's actually bothering you about pages sharing `TicketDetailScreen`/`CreateTicketScreen` with work tickets — visual clutter from irrelevant fields, or something more structural?
2. Should this stay a presentation-layer split (same `Ticket` entity/`TicketsCubit`, just a different screen widget/route), or does "different" imply a structurally separate creation/navigation flow too?
3. When you say "separate thing," how far does that go — a separate screen/route within the `tickets` feature, or pages becoming their own feature module entirely?
4. Given `project.md`'s hard no-cross-feature-import rule, does "own feature module" mean a presentation-only split (still the same `Ticket` entity/table/repository, accessed via a `core/contracts/` interface), or a fully separate entity/table independent of `Ticket`/`TicketType`?
5. Given the in-flight `page-content-markdown-editor` change already plans to wire `MarkdownEditor` into the existing shared `TicketDetailScreen`, should that change be paused/restructured now, or land as-is and be migrated later?

## Summary of answers

1. Both — irrelevant work-item fields clutter a page's UI, and there's a structural concern too.
2. Wants it to be a genuinely separate thing, not just a widget swap within the same screen/route.
3. A full, separate feature module — explicitly to avoid bloating the `tickets` feature.
4. Presentation-layer only: pages keep the existing `Ticket` entity, `TicketRepository`, and reuse `TicketsCubit`'s existing business logic; only screens/routes/UI-state move to a new `features/pages/` module, accessed from `tickets`' owned data via a `core/contracts/` interface per the existing Pattern 1 rule.
5. Pause and restructure the in-flight change now, since it's still only at the `/propose` stage (not yet applied) — cheaper to redirect now than migrate later.

## Conclusions reached

Introduce a new `features/pages/` module owning `page`-type-ticket screens
(`PageDetailScreen`, `PageCreateScreen`, and their own routes), replacing
`page`'s current use of the shared `TicketDetailScreen`/`CreateTicketScreen`.
This module:
- Renders only page-relevant fields (title, Markdown content via the
  planned `MarkdownEditor`, sub-pages tree, linked tickets, backlinks) —
  no priority/estimate/time-spent/status chrome.
- Does **not** introduce a separate entity or drift table — `page` stays a
  `Ticket` row (`TicketType.page`), preserving the already-shipped
  type-compatibility matrix, Markdown git-sync/embeddings pipeline, trash
  flow, and linked-tickets/backlinks infrastructure untouched.
- Depends on `tickets`-owned data (repository reads/writes, `TicketsCubit`
  business logic it needs to reuse — e.g. sub-page loading, sync status)
  through a new `core/contracts/` interface, per `project.md`'s existing
  Pattern 1 cross-feature rule — never a direct `import
  'package:aion/features/tickets/...'` from `features/pages/`.
- May introduce its own page-specific Cubit for UI-only state (e.g. the
  `MarkdownEditor`'s edit/view toggle, split-view layout) — this Cubit
  would not own ticket persistence/business logic, which stays behind the
  `core/contracts/` interface into `tickets`.

This was thought to directly supersede `page-content-markdown-editor`'s
plan (proposal.md/design.md as of this session) to branch
`TicketDetailScreen` on `ticket.type == page`. In fact that change's
`/apply` pass had already gone further than this session assumed: it
built the `features/pages/` module, `PageDetailScreen`/`PageCreateScreen`,
and the `core/contracts/page_ticket_provider.dart` interface described
above, and has since been archived. No restructure was required — this
idea's conclusion and the shipped implementation independently converged
on the same design.

## Open questions

- Exact shape of the new `core/contracts/` interface(s) needed (which
  `TicketsCubit`/`TicketRepository` operations `features/pages/` actually
  needs to call — sub-page loading, linked-tickets, backlinks, sync
  status, trash, at minimum).
- Whether `CreateTicketScreen`'s existing "+ New Ticket" type-picker flow
  still routes to `PageCreateScreen` for the `page` type, or whether page
  creation gets its own separate entry point (e.g. directly from the
  Documentation section's "+ New page" action, bypassing the generic
  picker entirely) — not resolved this session, left for `/propose` to
  decide as an implementation detail.
- Whether a page-specific Cubit is introduced now or deferred until
  `MarkdownEditor`'s UI-state actually needs it (could start as plain
  `StatefulWidget` state, per `project.md`'s "Cubit preferred, not
  required for pure UI state" allowance).

## Architectural implications

- Forces a new `core/contracts/` interface between `features/pages/` and
  `features/tickets/`, following [Pattern
  1](../project.md#cross-feature-dependencies) — the first real
  application of that pattern beyond its documentation in `project.md`.
- [[create-edit-and-delete-pages]]'s conclusion (Markdown-rendering editor,
  responsive toggle/split-view) is unaffected in substance — only *where*
  `MarkdownEditor` gets wired in changes, from `TicketDetailScreen` to the
  new `PageDetailScreen`.
- Builds on top of [[notion-obsidian-like-documentation-section]] (the
  Documentation section, page/resource tree, sub-page nesting) — this
  idea only moves *which screen* a page's detail/create flow renders, not
  the surrounding Documentation-section navigation structure.
- `page-content-markdown-editor` (now archived under
  `aion-arch/changes/archive/`) already targeted `PageDetailScreen` and
  delivered the `features/pages/` module and `core/contracts/` interface
  as part of its scope — no follow-up restructure needed.