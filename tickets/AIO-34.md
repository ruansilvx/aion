---
ticketId: AIO-34
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-12T00:00:00.000
updatedAt: 2026-08-13T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Idea, known gap, and open question as distinct ticket types

## Key questions asked

1. Should enumeration be scoped specifically to Documentation `page` tickets (matching the original `sdd-workflow-in-ticket-system` design), or generalized to any ticket type?
2. Is the itch mainly visibility (existing/future signal links buried in the generic Linked Tickets list), mainly creation friction (no quick way to raise a gap against a ticket), or both?
3. Should the rollup to parent tickets be fully recursive up the hierarchy, or just one level at a time?
4. Does renaming `signal` keep its current one-type-covers-idea/gap/question shape, or split into distinct types?
5. Should promotion-to-Epic/Bug stay meaningful for all three new types, or only for `idea`?
6. Should "a known gap/open question must be tied to an existing ticket" be a hard rule enforced in the Cubit, or just a convention?
7. Where should creation happen — the generic New Ticket flow with a required target field, or only reachable from the target ticket's own detail screen?
8. Should eliminating `signal` come with an automatic migration heuristic (e.g. based on existing relatesTo links), or manual reclassification?

## Summary of answers

- **Scope:** generalize to any ticket type, not just Documentation pages.
- **Primary itch:** visibility. `TicketDetailScreen` already has a generic Linked Tickets section where a `signal`-typed `relatesTo` link *can* already appear today, but undifferentiated among every other link type/target — no dedicated grouping. Creation friction was explicitly not the primary complaint, though the final design still changes creation flow as a consequence of other decisions.
- **Rollup:** fully recursive — an Epic's view must show gaps/questions raised on itself and on every descendant Story/Task/Bug, not just direct children.
- **Type split:** eliminate `signal` outright; replace with three real types — `idea`, `known gap`, `open question` — rather than keeping one type under a new name.
- **Promotion:** only `idea` keeps promote-to-Epic/Bug behavior. `known gap`/`open question` are never promoted — their only relationship to the rest of the system is the `relatesTo` link to the ticket they concern.
- **Target-ticket constraint:** hard rule, enforced in the Cubit — a `known gap`/`open question` cannot exist without a target ticket from the moment it's created.
- **Creation entry point:** only reachable from the target ticket's own detail screen (a dedicated affordance inside the new "Gaps & Open Questions" section), never the generic global New Ticket flow. Creates the ticket and the `relatesTo` link together, atomically. Documentation-mode sections (including Page tickets) also link/display these.
- **Migration:** manual reclassification of already-shipped `signal` tickets is in scope; no automatic heuristic-based migration.

## Conclusions reached

- Remove `TicketType.signal` entirely; add `TicketType.idea`, `TicketType.knownGap`, `TicketType.openQuestion`.
- `idea` inherits today's `signal` behavior wholesale: freestanding creation (no required target), always-root, promotable into `epic`/`bug` via the existing mechanism (narrowed/renamed from `promoteSignal`, e.g. `promoteIdea`).
- `known gap`/`open question` are structurally different: never promotable, never freestanding. A Cubit-level hard rule blocks creating either without specifying the target ticket, and creation itself only happens via a new affordance on that target ticket's own detail screen — not the generic New Ticket flow. The ticket and its `TicketLinkType.relatesTo` link to the target are created atomically in one action.
- A new "Gaps & Open Questions" UI section (distinct from the existing generic Linked Tickets section) is added everywhere Documentation-mode already exists — `epic`/`story`/`task`/`bug`/`resource`'s shared Documentation-mode sections, and `PageDetailScreen`'s equivalent for `page` tickets — so the scope isn't limited to pages the way the original `sdd-workflow-in-ticket-system` design implied.
- That section's data isn't a flat link list: it recursively aggregates `known gap`/`open question` tickets raised anywhere beneath the current ticket in the hierarchy (Epic → Story → Task/Bug), not just direct links on the ticket itself.
- Manual reclassification of pre-existing `signal` tickets (shipped via `sdd-ticket-foundation`) is in scope for this change — no automatic heuristic that infers `idea` vs. `known gap`/`open question` from existing link state.

## Open questions

- Exact UI copy/placement for the new section (this session used "Gaps & Open Questions" as a working label only).
- The existing Inbox chat purposes built around `signal` need follow-up changes not designed this session: `startBrainDump`'s classifier already only ever produces epic/bug-targeted ideas, so it likely just needs its output type renamed to `idea`; `startWhatNextGuidance`'s "Known gaps" markdown-section-scanning and "open signal tickets with no relatesTo" logic needs to shift to querying `known gap`/`open question`/`idea` directly instead.
- The manual reclassification UX itself (a one-off bulk tool? a per-ticket "reclassify" action surfaced wherever old `signal` tickets still exist?) wasn't designed — only confirmed to be in scope.
- Exact implementation shape of the recursive rollup query (new repository method vs. extending `TicketsCubit.loadDocumentRelations`) is left to `/propose`/`/design-sync`.
- Confirm the renamed promotion method's final name and signature (`promoteIdea` assumed here, not confirmed).

## Architectural implications

- Extends/modifies the shipped type-compatibility matrix (`define-type-compatibility-matrix`): removes `signal`, adds `idea`/`known gap`/`open question`, each needing their own always-root and parent/child rules (likely mirroring `signal`'s current no-parent restriction).
- Schema/drift migration: a `TicketType` enum change (one removal, three additions) — no new column needed, since the target-ticket relationship reuses the existing `TicketLink`/`relatesTo` mechanism rather than a new field.
- New Cubit-level validation for `known gap`/`open question` creation — never allow creation without a target ticket — consistent with [[feedback_cubit_domain_logic]]'s validation-lives-in-Cubits convention.
- `TicketsCubit.promoteSignal` narrows to only accept `idea` tickets; likely renamed.
- A genuinely new recursive-rollup query/repository capability, distinct from `TicketsCubit.loadDocumentRelations`'s flat per-ticket linked-tickets/backlinks query.
- New "Gaps & Open Questions" section is added generically across Documentation-mode ticket types and `PageDetailScreen`, not a page-only feature — supersedes the page-only scope implied by the original gap note in `aion-arch/specs/tickets.md`.
- Creation for these two types is removed from the generic New Ticket flow entirely, moving to a target-ticket-scoped affordance instead.
- Requires follow-up changes to the already-shipped Inbox `startBrainDump`/`startWhatNextGuidance` chat purposes (see Open questions) — flagged, not designed here.
- Manual reclassification of existing `signal` tickets is in scope; mechanism undesigned.
- Builds on and supersedes part of [[sdd-workflow-in-ticket-system]]'s Follow-up decisions — that session deliberately unified idea/gap/open-question into one `signal` type "to cover all three without implying any one specifically"; this session reverses that specific call now that gaps/open-questions are getting dedicated rollup/visibility treatment that ideas don't need.