---
ticketId: AIO-75
type: epic
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-09-02T21:17:20.135559
updatedAt: 2026-09-02T21:17:20.135559
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Ai Assisted Complexity And Estimate Suggestions

# Proposal: AI-assisted complexity and estimate suggestions

## Why

`Ticket.complexity` (`TicketComplexity?` — small/medium/large) and
`Ticket.estimate` (`int?` minutes) are today plain, manual-entry-only
fields — `null` until the user sets them by hand via the detail screen's
Complexity picker and Estimate inline field. This is a known gap in
`aion-arch/specs/tickets.md`: "No automated estimation consuming
`Ticket.complexity` — plain user-set field, same treatment `estimate`/
`timeSpent` already get." For a solo dev moving fast through a backlog,
sizing every ticket by hand is friction that a rough automatic first
guess — visibly flagged, easily overridden — removes without taking away
control.

See `aion-arch/ideas/ai-assisted-complexity-and-estimate-suggestions.md`
for the full brainstorm session this proposal is built from.

## What

Add an automatic, per-field AI-assisted suggestion mechanism for
`complexity` and `estimate`:

- **Trigger**: fires on the same events `_triggerEmbeddingRegen` already
  does — always on ticket create, and on update only when title/
  description changed. Runs unawaited in the background; never blocks a
  save.
- **Model tier**: `ModelPhase.capable` (mechanical-weight, `noTools`),
  resolved the same way every other phase-routed call in `TicketsCubit`
  already is.
- **Calibration context**: a brute-force cosine-similarity scan (per
  `project.md`'s Foundational Decision #1) over every other live ticket
  that already has `complexity`/`estimate` set, ranked by embedding
  similarity to the ticket being estimated. Up to 5 comparable tickets'
  title/description + their sized values are included in the prompt as
  few-shot calibration examples.
- **Cold start**: if zero comparable tickets are found, the model still
  produces a content-only guess from title/description alone — surfaced
  as visibly lower-confidence, never skipped.
- **Flagging**: every AI-produced value is visibly marked as AI-generated
  (and, when applicable, low-confidence) in the UI — never
  indistinguishable from a manual entry.
- **Locking, independent per field**: editing `complexity` or `estimate`
  by hand (through the existing picker/inline field) locks that specific
  field as user-set. A locked field is permanently skipped by the
  automatic background trigger. An explicit "Regenerate" action lets the
  user ask for a fresh AI suggestion on a locked field on demand — which
  then unlocks it again (back to auto-eligible) until edited by hand
  again.
- **Rollup interaction**: unchanged — `estimate` participates in the
  existing `estimateRollup` recompute walk regardless of whether its
  current value is AI-suggested or manual (see
  `aion-arch/specs/tickets.md`'s [Estimate/timeSpent
  rollup](../../specs/tickets.md#estimatetimespent-rollup)).

## Scope

**In scope**: `TicketsCubit`'s create/update paths, a new
`TicketEstimationSuggester` orchestrator (mirrors
`TicketRollupRecomputer`'s placement/shape), a new `TicketRepository`
method for writing a suggestion without perturbing `updatedAt` (mirrors
`updateEmbedding`/`updateRollup`), a `complexitySource`/`estimateSource`
column pair on `Ticket`/`TicketsTable`, and UI on the **ticket detail
screen only** — the Complexity picker and Estimate field each grow an
AI-suggested/low-confidence badge, and a Regenerate action appears when
locked.

**Out of scope** (see also the idea file's Open questions):

- List rows and board cards showing an AI-suggested badge — today's
  `ComplexityMeter` in those contexts has no label space for one, and the
  brainstorm session left this ambiguous. A follow-up idea, not this
  slice.
- Triggering estimation from a hand-edited `resource`/`page` markdown
  file's title/description change (via `TicketMarkdownWatcherService`) —
  `complexity`/`estimate` are not projected into ticket Markdown at all
  today (confirmed: `TicketGitProjector` never writes either field), and
  those ticket types rarely carry a meaningful complexity/estimate in
  practice. In-app Cubit-driven create/update only, matching exactly
  where `_triggerEmbeddingRegen` already fires.
- A live push/refresh of an open `TicketDetailScreen` once a background
  suggestion lands — matches the existing precedent of every other
  fire-and-forget background write in `TicketsCubit`
  (`_triggerEmbeddingRegen`, `_recomputeRollupChain`,
  `_triggerGitProjection`): persisted silently, picked up on next fetch/
  reopen. The user-invoked "Regenerate" action is the one exception —
  it's awaited and re-emits `TicketDetailLoaded` immediately, since it's
  a direct response to a button press, not a passive background event.
- Any numeric confidence score self-reported by the model — "low
  confidence" is derived deterministically by Aion itself (zero
  comparable tickets found), not requested from or trusted from the
  model's own output.
- Configuring how many comparable tickets to pull, or the model tier,
  from Settings — fixed at 5 and `ModelPhase.capable` respectively for
  this slice.

## Design gate

status: APPROVED

Approved: 2026-08-11. No Material-widget violations found in the Claude
Design export (design.md §§0–5). 2 new color tokens to add to
`aion_colors.dart` before `/apply` — `primaryWash(bool isDark)`,
`focusRing(bool isDark)` (exact copy-paste blocks in the
`/design-sync` Step 2 output, aion-arch commit history) — plus one new
typography token, `AionText.badgeLabel`, in `aion_text.dart`. Every
other token the export references (`primary`, `surfaceHover`,
`textPrimary`/`textSecondary`/`textMuted`, `neutralTint`/
`neutralBorderTint`) already exists. `tasks.md` §5.1/§5.2 are annotated
with their corresponding design.md sections.
