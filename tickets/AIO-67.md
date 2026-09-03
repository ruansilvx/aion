---
ticketId: AIO-67
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-08T00:00:00.000
updatedAt: 2026-08-12T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Ticket-graph and embedding context enrichment for spawned chats

## Key questions asked

1. Which side of "the model wastes effort discovering context itself" is actually the concern — the ticket graph (linked/related tickets) or the project's source code?
2. To confirm scope: is this about ticket-linked documentation (already in Drift, already embedded) rather than the actual project source tree (out of scope, no plans to change that)?
3. Should v1 pre-resolve only the structured, explicitly-linked graph (parent chain + direct `TicketLink` rows via Drift), or also reach for embedding similarity to surface related-but-not-explicitly-linked tickets?
4. Should this enrichment apply only to coding execution (the one stage with `toolsEnabled: true`, where tool-call waste is real), or also to the SDD-stage chats (`designBrief`/`designSync`/decomposition), which have no tool access at all but still work from thin context?
5. For the embedding-similarity walk feeding an automatic (non-human-typed) context assembly: fixed top-K, or a similarity-threshold cutoff?

## Summary of answers

- The concern is squarely about the **ticket graph**, not source code — Aion has no plans to build source-code-level context enrichment (repo-map, symbol index); tickets are the only structure it reasons over.
- Grounded finding: SDD-stage chats (`designBrief`/`designSync`/decomposition) run with `toolsEnabled: false` — no file/git/bash access at all, so there's no live tool-call waste happening there today. **Coding execution is the only stage with `toolsEnabled: true`**, and its `_assembleExecutionContext` currently passes zero linked-ticket content — just title/description + baseline conventions. So today, a Task needing its parent Story's other Tasks, a `blockedBy` ticket's notes, or the linked design Page has to `grep`/read `tickets/<id>.md` inside the worktree itself, tool call by tool call.
- Wants **both** pieces: a structured Drift walk (parent chain + direct links, generalizing `designSync`'s existing single-link walk) and an embedding-similarity walk, since the embedding infrastructure is already in place and cheap to extend — `Ticket.embedding` is already populated on every create/edit (on-device, no cloud call), and `TicketDocumentSearchService` already does brute-force cosine similarity (the accepted pattern per `project.md`'s Foundational Decision #1), just scoped today to `page`/`resource` tickets for the Documentation search box.
- Wants the enrichment applied to **both** coding execution (saves tool calls) and the SDD-stage chats (richer context even without tool access, purely a context-quality improvement there).
- Embedding inclusion should be **threshold-based** (only include tickets above a similarity cutoff — could be zero results), with a **top-K cap as a fallback safety net** to bound context size, not a fixed top-K that always injects weak matches.

## Conclusions reached

Build one shared context-enrichment helper, called from both `_assembleExecutionContext` (coding execution) and `_createStageChat` (SDD-stage chats), that combines:

1. **Structured walk** (Drift-backed, via `TicketLinkRepository`/parent-chain lookup) — generalizes `designSync`'s existing single-link walk to cover the full parent chain plus every direct `TicketLink` row (`blocks`/`blockedBy`/`relatesTo`/`duplicates`), for any ticket type, not just the one hardcoded design-Page link.
2. **Embedding-similarity walk** (widening `TicketDocumentSearchService`'s existing cosine-similarity search beyond `page`/`resource` to all ticket types) — embeds the source ticket's own title+description as the query, includes results above a similarity threshold, capped at a top-K fallback, and excludes any ticket already surfaced by the structured walk (no duplication).

This directly targets the identified waste: coding execution's tool-enabled model no longer needs to spend tool-call turns rediscovering ticket-graph context Aion can resolve itself in milliseconds, and SDD-stage chats get materially richer context than today's bare title/description.

## Open questions

- Exact similarity threshold and top-K cap values — needs tuning, not yet decided.
- How large the assembled context is allowed to get before it risks crowding out the model's actual task instructions (a context-size budget wasn't discussed this session).
- Whether `retryDesignSync`'s own context-reassembly path (which re-fetches the linked Page's *current* content on retry) needs any special handling once the walk is generalized, or whether the same shared helper just works there too.
- Ticket-edit/delete staleness during an in-flight run was raised but not resolved in depth — leaning toward "acceptable as a one-shot snapshot," consistent with how `designSync`'s context already behaves, but not explicitly confirmed.
- Split off this session into its own idea: whether ticket CRUD *during* coding execution should also be delegated to Aion rather than attempted via file writes — see [[delegate-ticket-crud-to-aion-during-coding-execution]].

## Architectural implications

- Generalizes `designSync`'s existing single-link Drift walk into a shared, type-agnostic helper reused by multiple call sites.
- Widens `TicketDocumentSearchService`'s scope from "Documentation search box, `page`/`resource` only" to "any ticket type, any caller" — same brute-force cosine mechanism, no new dependency, reinforcing (not challenging) `project.md`'s Foundational Decision #1 ("brute-force cosine similarity... sufficient at personal scale").
- Touches `TicketsCubit._assembleExecutionContext` (coding execution) and `TicketsCubit._createStageChat` (SDD-stage chats spawned by `advanceSddStage`), and likely `retryDesignSync`'s context-reassembly path.
- Directly closes the known gap already recorded in `tickets.md`: "No repo-map-lite or embedding-based context enrichment for a spawned SDD-stage chat's initial message — plain-text parent fields and direct hierarchy/`relatesTo` links only, no similarity search, no tree-sitter symbol index." (Repo-map-lite/tree-sitter symbol indexing over source code remains explicitly out of scope — ticket-graph only.)