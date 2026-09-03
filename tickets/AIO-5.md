---
ticketId: AIO-5
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-11T00:00:00.000
updatedAt: 2026-08-11T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# AI-assisted complexity and estimate suggestions for tickets

## Key questions asked

1. Is this idea about building automated/AI-assisted estimation, or about
   explicitly deciding to keep `Ticket.complexity` manual-only and closing
   the gap with reasoning?
2. Should estimation run automatically (like embedding generation) or
   on-demand (user explicitly requests it)?
3. Once a user manually edits an AI-suggested value, does it lock
   permanently against future auto re-estimates, or keep getting
   re-suggested/overwritten as content changes?
4. Which `ModelPhase` tier should drive the estimation call — `capable`
   (mechanical) or `frontier` (heavier judgment)?
5. What context should Aion gather for the model to calibrate against —
   just the ticket's own title/description, or also comparable historical
   tickets?
6. Cold-start case: no comparable historical tickets exist yet (new
   project, or a type with none sized). Skip silently, or still produce a
   content-only guess?
7. Should the AI-suggested/locked state be tracked per-field
   independently (complexity and estimate each lockable on their own), or
   as one combined flag?

## Summary of answers

1. Build automated/AI-assisted estimation — for both `complexity` and
   `estimate` (not `timeSpent`, which tracks actuals rather than a
   forecast).
2. Automatic — fires in the background the same way embedding generation
   already does, but every suggestion is explicitly flagged as
   AI-generated so the user knows it may be inaccurate.
3. Locked once edited — a manual edit is final and future automatic
   re-estimates never touch that field again. The user can still
   explicitly ask the model to regenerate a suggestion later. Manual (or
   AI-set) `estimate` changes continue to trigger the existing rollup
   recompute walk up the ancestor chain exactly as today.
4. `capable` — this is treated as mechanical inference from ticket
   content, not epic/story-level judgment, matching `ModelPhase.capable`'s
   existing definition ("comparatively mechanical work"). Since
   `capable`/`frontier` calls are `noTools`, any "leverage the database"
   behavior has to be Aion gathering context up front, not the model
   querying live.
5. Comparable historical tickets, for calibration — reusing the existing
   `TicketRepository.searchTickets` brute-force cosine-similarity search
   over ticket embeddings (`ticket_document_search_service.dart`),
   filtered to tickets that already have the target field
   (`complexity`/`estimate`) set, rather than title/description content
   alone.
6. Still run, producing a content-only guess, clearly caveated as
   low-confidence — never silently skip.
7. Independent per field — a user can lock `complexity` as user-set while
   `estimate` remains a live, re-suggestable AI value, and vice versa.

## Conclusions reached

Build automatic, per-field AI-assisted estimation for `Ticket.complexity`
and `Ticket.estimate`:

- **Trigger**: fires on the same events as embedding generation
  (create/title/description-change), running in the background — no
  on-demand-only path for the automatic case (a manual "regenerate"
  action still exists for a locked field, per below).
- **Model tier**: `ModelPhase.capable` — mechanical-weight, cheap,
  `noTools`. Not `frontier`.
- **Context gathering**: Aion-side, not model tool-calls (since `capable`
  is `noTools`). Reuses the existing `TicketRepository.searchTickets`
  cosine-similarity search, filtered to comparable tickets that already
  have the target field set, as few-shot calibration examples in the
  prompt. No new search infrastructure needed — this is new orchestration
  over an existing capability.
- **Cold start**: if no comparable tickets exist yet, still produce a
  content-only guess from title/description alone, visibly caveated as
  low-confidence rather than skipped.
- **Flagging**: every AI-produced value is visibly marked as AI-generated
  in the UI — never indistinguishable from a manually-entered value.
- **Locking**: editing `complexity` or `estimate` manually locks that
  *specific* field as user-set, independently of the other. A locked
  field is permanently excluded from automatic re-estimation; the user
  can still explicitly trigger a fresh AI suggestion for a locked field
  later (an explicit "regenerate" action, distinct from the automatic
  background trigmer).
- **Rollup interaction**: AI-set (and manually-edited) `estimate` values
  continue to feed the existing `estimateRollup` recompute walk up the
  ancestor chain exactly as today's manual-entry values do — no special
  casing needed there, since the rollup mechanism reads whatever value
  sits in `estimate` regardless of its source.
- **New surface**: a per-field "source" state (manual vs. AI-suggested)
  needs to be added to `Ticket` for both `complexity` and `estimate` —
  requires a DB migration (following the existing versioned-migration
  pattern used for `complexity`/`sdd_stage`) and markdown projection
  updates. The lock/regenerate/re-suggest invariant logic belongs in a
  Cubit (likely `TicketsCubit`), not pushed down into a repository or
  service, per [[feedback_cubit_domain_logic]].
- **No new dependency**: everything this needs is already shipped —
  `ModelPhase.capable` routing (`per-phase-tier-based-model-routing`,
  archived), embedding generation triggers, and
  `TicketRepository.searchTickets`. This is new orchestration, not new
  infrastructure.

## Open questions

- Exact shape of the per-field "source" state — a two-value enum
  (`manual | aiSuggested`) per field, or a boolean pair — left for
  `/propose` to design.
- How many comparable historical tickets to pull as calibration examples,
  and how to handle a project with *some* but very few sized tickets
  (partial cold-start) — left for `/propose`.
- Where exactly the "AI-generated" flag and "regenerate" action render in
  the UI (detail screen only, or also list rows/board cards where
  `ComplexityMeter` already appears) — this touches existing
  widgets (`ComplexityMeter`, the estimate field), so `/propose` should
  expect the design gate to come back `PENDING`.
- Whether a locked field's "regenerate" action should also let the
  comparable-ticket search radius or model tier be adjusted, or just
  re-run with the same defaults — not discussed this session.

## Architectural implications

- Touches `Ticket` (new per-field source state), its DB schema (new
  migration), and markdown projection — same shape as the existing
  `complexity`/`sdd_stage` migration precedent in `tickets.md`.
- Touches `TicketsCubit` (or a related Cubit) for the
  lock/regenerate/re-suggest invariant logic, per
  [[feedback_cubit_domain_logic]].
- New background orchestration service, analogous to how embeddings are
  generated asynchronously today: on trigger, checks per-field lock
  state, gathers comparable tickets via `TicketRepository.searchTickets`,
  calls `ModelRoutingRepository.getModelForPhase(ModelPhase.capable)`,
  and writes the suggestion back with its AI-generated flag set.
- Interacts with the already-shipped estimate rollup
  ([[estimate-timespent-rollup-for-ticket-hierarchy]]) — AI-set estimates
  participate in the same recompute walk, no special-casing needed.
- Touches ticket detail screen (and possibly list rows/board cards) for
  the AI-generated badge and regenerate action — multi-widget UI surface,
  so `/propose` should expect the design gate to come back `PENDING`.
- Builds on already-shipped infra only:
  [[per-phase-tier-based-model-routing]] (`ModelPhase.capable`) and the
  existing embedding-similarity search — no new provider/routing work
  required.