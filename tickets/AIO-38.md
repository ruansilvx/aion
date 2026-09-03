---
ticketId: AIO-38
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-17T00:00:00.000
updatedAt: 2026-08-17T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Live-refresh an open ticket detail screen on background writes

## Key questions asked

1. Is there a specific pain point driving this, or is it a cold assessment
   of the four documented AI-suggestion gaps
   ([tickets.md:6321](../specs/tickets.md)) to decide which are worth
   closing?
2. List/board badge gap: does knowing a value is an AI guess (vs.
   confirmed) matter when scanning the list/board, or only once already
   inside a ticket's detail?
3. Live-push gap: is "leave and reopen to see an update" a real
   annoyance, or does it match how you'd naturally interact with a
   ticket anyway?
4. Should this brainstorm solve the live-refresh problem generally
   (also closing the near-identical `canAdvanceSddStage` staleness gap,
   [tickets.md:6332](../specs/tickets.md)), or stay scoped narrowly to
   the AI-suggestion case?
5. Model self-reported confidence score gap: worth adding, or is Aion's
   deterministic zero-comparable-tickets signal good enough?
6. Settings-level config (comparable-ticket count, model tier) gap:
   worth exposing, or fine fixed indefinitely?

## Summary of answers

1. No specific pain yet — cold assessment of all four gaps.
2. Not really — the badge distinction only matters once already looking
   at a ticket's detail, not while scanning list/board.
3. Real annoyance — the value should update live while the screen is
   open, not require a manual reopen.
4. Solve it generally — cover both the AI-suggestion case and the
   `canAdvanceSddStage` case with one mechanism.
5. No — confidence should stay derived from how many similar/developed
   tickets exist for calibration, not self-reported by the model.
6. No — fixed defaults (5 comparable tickets, `ModelPhase.capable`) are
   fine. Might revisit in the future, but explicitly not now.

## Conclusions reached

Build a general live-refresh mechanism for `TicketDetailScreen`, scoped
to writes that happen while that exact ticket's detail is already open:

- **Mechanism**: `TicketsCubit` is a single app-wide instance, provided
  once by `WorkspaceShell` ([tickets.md:1208](../specs/tickets.md),
  [:5852](../specs/tickets.md)) — not a fresh instance per screen. Since
  `TicketEstimationSuggester` (and every other background/foreground
  write path) already runs through that same instance, no new
  stream/watch/pub-sub layer is needed. Extend the existing
  re-emit-after-write pattern (already used after direct edits like
  `updateTicketStatus`) so that after a background write completes, the
  cubit checks "is my current state `TicketDetailLoaded` for the
  affected ticket, or for a ticket whose computed fields depend on the
  affected ticket (e.g. a parent Story when a child Task's status
  changed)?" — if so, re-fetch/re-emit; otherwise no-op.
- **Covers two gaps at once**:
  1. The AI-suggestion live-push gap
     ([tickets.md:6325](../specs/tickets.md)) — `TicketEstimationSuggester.suggest()`
     landing a value while that ticket's own detail screen is open.
  2. The `canAdvanceSddStage` staleness gap
     ([tickets.md:6332](../specs/tickets.md)) — a sibling Task's status
     change while its parent Story's detail screen is open, currently
     requiring a manual reload to flip the banner/button.
- **Explicit Regenerate path is unaffected** — it already re-emits
  immediately today; this only closes the gap for the *passive*
  background path.
- **Three sibling gaps decided closed, not deferred**:
  - **List/board badge**: not worth building — the AI-vs-confirmed
    distinction only matters once already inside a ticket's detail.
  - **Model self-reported confidence score**: not worth building —
    confidence should stay derived deterministically from how many
    comparable, already-sized tickets exist to calibrate against, not
    requested from the model itself.
  - **Settings-level config** (comparable-ticket count, model tier):
    not worth building now — fixed defaults (5 tickets,
    `ModelPhase.capable`) are fine; may revisit later but explicitly
    not a near-term need.

## Open questions

- Exact predicate for "does this write affect the currently-open
  ticket" — direct match (same `id`) is trivial; the parent/ancestor
  case (`canAdvanceSddStage`) needs the cubit to know which written
  ticket's `parentId` chain reaches the currently-loaded one. Left for
  `/propose` to design precisely (likely: check `parentId` equality
  against the loaded Story's `id` for a Task/Bug status write, mirroring
  how `getTicketById` already computes `canAdvanceSddStage` today).
- Whether this re-emit check should live as one shared private helper
  on `TicketsCubit` called from every relevant write path (estimation
  suggestion apply, status update, etc.), or per-call-site logic — left
  for `/propose`.
- Not discussed: whether any *other* background-mutating path beyond
  these two (estimation suggestion, sibling status change) should also
  be swept into the same general mechanism while it's being built.

## Architectural implications

- Touches `TicketsCubit` only — no new widget, no new DB migration, no
  new provider/service. Pure Cubit-layer orchestration, consistent with
  [[feedback_cubit_domain_logic]] (this kind of "is my current state
  affected, should I re-emit" judgment belongs in the Cubit, not pushed
  into `TicketRepository`).
- No new reactive infrastructure (no Drift `.watch()` streams, no
  cross-cubit event bus) — relies entirely on `TicketsCubit` already
  being a single app-wide instance rather than screen-scoped, per
  [tickets.md:1208](../specs/tickets.md)/[:5852](../specs/tickets.md).
- Directly closes two gaps documented in
  [tickets.md:6321-6335](../specs/tickets.md) without touching the other
  three gaps listed alongside them, which this session explicitly
  decided to leave closed.
- Builds on [[ai-assisted-complexity-and-estimate-suggestions]] (already
  archived/shipped) without reopening its design — this is additive
  orchestration on top of it, not a revision.