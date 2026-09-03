---
ticketId: AIO-63
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-26T00:00:00.000
updatedAt: 2026-08-26T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Native spec ticket kind, auto-written by the SDD cycle

## Key questions asked

1. What problem does file-based spec staleness actually solve/break?
   (Superseded — see correction below.)
2. (User correction) This is not an `aion-arch` discussion, but a
   question about Aion's own product-level spec concept.
3. Should a spec be its own distinct kind, or a convention/marker on
   top of the existing generic `page` ticket type?
4. How is a spec scoped — one per domain/capability, or one per Epic?
5. What makes more sense given ease-of-update, token cost, and
   organization concerns?
6. Would domain tags on ticket metadata be a useful grouping mechanism?
7. Does only the Epic get a spec ticket, or does each Story also get
   one, rolling up into the Epic's?
8. (Follow-up round) Between a new type and a `page` field, which is
   recommended?
9. Is `aion-arch` a permanent second system, or transitional?
10. Should Epics ever be reopened/extended, or should specs be updated
    directly instead?
11. Does spec-writing go through the same explore→propose→apply→
    verify→archive cycle as everything else?
12. Should links from other tickets (bugs solved, open questions, etc.)
    to a spec be automatic?
13. What should the similarity-search mechanism for automatic linking
    be — is reusing Aion's existing embedding-backed search a good fit?
14. Should the auto-link similarity threshold match the existing 0.75
    used elsewhere, or be stricter given the higher stakes of an
    autonomous write?
15. Does `project.md` have a ticket-system equivalent today?
16. Is `project.md` the same kind of thing as a `spec`, or different
    enough (agent-constitution vs. product content) that "every
    aion-arch element should have a ticket-solution equivalent" needs
    its own scoping?

## Summary of answers

- The topic is scoped to Aion as a product, not `aion-arch`'s own
  file-based convention — and specifically, this is meant to
  **eventually fully replace** `aion-arch/specs/*.md`, not coexist with
  it indefinitely. `aion-arch` exists only while Aion isn't yet able to
  self-iterate; once it can, `aion-arch` itself gets converted into
  Aion's own ticket system and the repository is deprecated. This
  raises the bar on the mechanism: it eventually has to be Aion's
  *only* record of its own current-state behavior.
- Spec is its own distinct kind (`TicketType.spec`), not a convention
  on `page`. Reasoning: structural rules (parentless, always linked to
  its originating Epic via `relatesTo` rather than nested) are enforced
  for free by `TicketTypeHierarchy` when it's a real type — a
  `page.kind` marker gets none of that, and would require bolting
  exception logic onto `page`'s otherwise-unconditional nesting rules.
  Reliable lookup (`WHERE type = 'spec'`) also matters more once this
  is the sole record of Aion's own behavior. Matches this project's own
  precedent (`release`, `knownGap`, `openQuestion` each got dedicated
  types rather than repurposing an existing one). No real cost — a
  dedicated type can still reuse `page`'s existing Markdown
  content-editing widget, same as other ticket types already share
  components without sharing an enum value.
- Scoping resolved to per-Epic over per-domain-merged-file: per-domain
  requires real merge/editorial-judgment logic against an
  ever-growing document — unbounded token cost as a domain matures.
  Per-Epic needs no merge logic: the Archive-stage chat's own output
  becomes the spec ticket's content on creation.
- Domain-level grouping across many Epics' specs is deliberately not
  built now — `relatesTo` links/page nesting already do that job, and
  the not-yet-built [[obsidian-style-graph-view-for-ticket-links]] idea
  will make it visually browsable later. No dedicated index/rollup
  page, no new tagging mechanism (a flat freeform tag has no
  traversal, no backlinks, no taxonomy hygiene, and duplicates a job
  `relatesTo` already does better — consistent with this project's
  precedent of reusing `relatesTo` instead of adding new fields).
- Only the Epic gets a spec ticket, written exactly once. An Epic only
  ever reaches `verifying`/`archived` after every child Story has
  already reached `SddStage.archived` itself (existing precondition),
  so the Epic's spec-writing step happens once with full context of
  every finished Story already at hand — no accumulate-and-merge
  problem even at Epic scope.
- Epics are never reopened or extended. Once archived, an Epic is
  immutable; the spec ticket it produced is the mutable surface
  afterward — corrections, linking resolved bugs, etc. happen as plain
  content edits on the spec ticket itself (same mechanism as editing
  any Documentation page today), fully decoupled from the Epic's own
  lifecycle.
- Spec-writing does not go through its own explore→propose→apply→
  verify→archive cycle. It's a mechanical side effect of the Epic's own
  Archive stage — the Epic went through the full cycle; the spec write
  is one step inside that Epic's `archived` transition. Post-creation
  edits are direct, not routed back through the cycle. Mirrors exactly
  how the CLI's `/archive` writes to `aion-arch/specs/` today: a
  mechanical merge step at the tail of a change's own cycle, never its
  own change.
- Links to a spec from other tickets should be automatic wherever
  possible, but the mechanism differs by case:
  - **Structurally-traceable tickets** (a Task, or a Bug parented
    directly under the same Epic/Story) need no new link — the
    existing `parentId` chain (Task → Story → Epic → spec via
    `relatesTo`) already makes the connection derivable. Materializing
    an explicit link per Task would just clutter the spec's linked-
    tickets section with redundant entries an Epic with many Tasks
    would spam.
  - **Tickets with no structural path** (a Bug found well after the
    Epic archived, a fresh `openQuestion`/`knownGap` raised against
    shipped behavior) get auto-linked via Aion's existing
    embedding-similarity scan — the same brute-force cosine-similarity
    pattern `TicketContextEnricher`/`TicketEstimationSuggester`/
    `TicketDocumentSearchService` already use (per `project.md`'s own
    Foundational Decision that brute-force similarity is sufficient at
    personal scale), scanning specifically against `TicketType.spec`
    tickets, reusing the same 0.75 threshold unchanged rather than a
    stricter bar. No new embedding/indexing infrastructure needed —
    every ticket already gets one on `createTicket`/`updateTicket`.
  - This is the first consumer where a similarity match **autonomously
    creates a write** (a persistent `relatesTo` link) rather than just
    enriching a prompt or suggesting a value — every existing consumer
    stops short of that. Gated by the existing three-state
    `AutomationConfidence` (`auto`/`gated`/`manual`), the same pattern
    already built for SDD-stage-triggering — reusing that type as its
    second real consumer rather than inventing a new automation
    concept.
- `project.md` has no ticket-system equivalent today. The source idea
  ([[sdd-workflow-in-ticket-system]]) explicitly treated it as a
  *different* question from `specs/*.md` — agent-constitution content
  (how to behave) versus product content (what exists) — and left it
  undecided; neither `sdd-ticket-foundation` nor `sdd-ticket-execution`
  touched it. Resolved here: it's the same kind of thing as a spec, and
  folds into this same mechanism as **one architecture spec ticket** —
  not tied to any single Epic's archival, since `project.md` predates
  and outlives any one Epic (creation/update trigger for this
  particular ticket is an open question, see below).
- "Every element of aion-arch should have a ticket-solution
  equivalent" is real but bigger than this idea. `specs/*.md`,
  `project.md`, and the `changes/<name>/` artifacts (proposal/design/
  tasks/delta-spec) are covered by this idea and by what's already
  shipped. Everything else — the ~50 existing `ideas/*.md` files'
  migration, `changes/archive/*` history's fate, `CLAUDE.md`/
  `workflow/`'s CLI-process docs, and ultimately retiring
  `.claude/skills/` itself — is deliberately out of scope here, split
  off as [[decommission-aion-arch-cli-workflow]] to keep this idea
  landable as one proposal.

## Conclusions reached

Aion gets a native `TicketType.spec`, created automatically and exactly
once when an Epic's `advanceSddStage` reaches `archived`, as a
mechanical step inside that transition (not its own SDD cycle). It's
meant to eventually fully replace `aion-arch/specs/*.md` once Aion can
self-iterate. `project.md` is the same kind of thing and folds into
this mechanism as one architecture spec ticket. Epics are never
reopened; every spec ticket (including the architecture one) is
directly editable afterward. Other tickets link to a spec automatically
where there's no structural path already — via the existing
embedding-similarity scan at the existing 0.75 threshold, gated by
`AutomationConfidence`. Domain-level grouping across specs is left to
existing linking/search and the future graph view, not built here. The
rest of aion-arch's decommissioning is a separate idea.

## Open questions

- What creates and updates the architecture spec ticket, given it
  isn't produced by any single Epic's archival the way every other
  spec is. Candidates: bootstrapped once by hand, then updated as
  foundational decisions in it get resolved via `/brainstorm`/
  `/propose`-equivalent ticket-native flows; or written/refreshed by
  some other trigger not yet designed. This is the one spec ticket
  whose lifecycle doesn't fit the "write-once-at-Epic-archive"
  mechanism the rest of this idea establishes.
- Whether the Epic-level Archive-stage chat needs richer context than
  today's `verifying`/`archived` assembly (currently just direct
  children's titles/statuses) to write a spec worth reading later —
  e.g. pulling in each Story's own linked Documentation pages.
- The concrete UI for editing a spec ticket after creation (reuses
  `page`'s content-editing widget per this session's reasoning, but not
  confirmed against current screen structure).
- Whether/how a Bug's move to `done` (the trigger point named for
  auto-linking) interacts with `TicketsCubit`'s existing coding-
  execution completion flow, versus firing as a separate check.
- Exact `TicketTypeHierarchy` entry for `spec` (`canParent`/
  `isAlwaysRoot` — almost certainly parentless like `release`, but not
  confirmed against current code) and its `CreateTicketScreen` slot,
  if any (a spec is machine-created, not human-authored via the
  generic New Ticket flow — likely excluded from that dropdown
  entirely, same as `knownGap`/`openQuestion`).

## Architectural implications

- Depends on/splits off from [[sdd-workflow-in-ticket-system]], which
  originally floated "specs-as-pages" and left it an explicitly
  undecided, out-of-scope question in both `sdd-ticket-foundation` and
  `sdd-ticket-execution`.
- Depends on [[obsidian-style-graph-view-for-ticket-links]] (currently
  `status: raw`, unexplored) for the domain-grouping visualization this
  idea deliberately defers rather than building its own rollup UI for.
- Extends `TicketTypeHierarchy` (parent/child rules, `isAlwaysRoot`) and
  the existing type-compatibility matrix test, same shape as
  `sdd-ticket-foundation`'s `signal`/`release` additions.
- No new merge/diff Cubit logic required. Spec-ticket creation at
  Epic-archive time can reuse the existing `_createStageChat`/child-
  ticket-creation pattern (`TicketRepository.createTicket`) already
  used by `_materializeDecomposition` for Propose-stage decomposition.
- Auto-linking reuses `domain/utils/embedding_similarity.dart`'s
  `cosineSimilarity` and the existing `EmbeddingProvider` plumbing —
  no new embedding generation or indexing work. Becomes
  `AutomationConfidence`'s second real consumer alongside SDD-stage-
  triggering, and its first consumer where a similarity match drives an
  autonomous write rather than prompt enrichment or a suggested value.
- Long-term implication flagged, not resolved here: once this fully
  replaces `aion-arch/specs/*.md`, the CLI-driven `/archive` skill's
  spec-merge step (and eventually the whole `aion-arch/.claude/skills/`
  pipeline) becomes redundant for Aion's own development — a much
  larger, separate migration this idea doesn't attempt to scope.