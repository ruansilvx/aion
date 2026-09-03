---
ticketId: AIO-70
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-13T00:00:00.000
updatedAt: 2026-08-17T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Token Cost Prediction

## Key questions asked

1. What's the actual moment this needs to show up at — pre-flight estimate, running total, or both?
2. Which kinds of runs should get a pre-flight estimate — coding execution, SDD-stage chats, Inbox chats?
3. Should the pre-flight estimate be purely informational, or a real gate?
4. When there's no comparable history to calibrate against, what should the estimate show?
5. For the running total during an in-flight run, where should it live and how live does it need to be?
6. Given Aion's flat-rate Pro/Max plan (no real $ amount available), what should the pre-flight number actually be expressed as?
7. Where should the pre-flight estimate be visible before a run starts, given coding execution has no dedicated "Start Run" button?

## Summary of answers

- Primary need: a pre-flight estimate shown before starting a run. A running total during/after execution is also desired, not a replacement.
- Scoped to coding execution only (Task/Bug tickets) — not SDD-stage chats or Inbox chats.
- Purely informational — no confirmation gate, unlike `AutomationConfidence.gated`'s pause-and-confirm pattern.
- No comparable history → show "no estimate available" rather than a fabricated coarse fallback.
- Running total: live-updating on the Task/Bug detail screen's execution banner, and also visible on the Board card/list tile.
- Expressed as a raw token count/range (e.g. "~45K–89K tokens"), not a qualitative bucket or a dollar amount — matches what's actually stored and avoids inventing a cost figure Aion's flat-rate provider can't truthfully report.
- Pre-flight estimate placement: a persistent label on the Task/Bug detail screen, and also on the Board card/list tile, visible before execution is ever triggered (not just at the inProgress-transition moment).

## Conclusions reached

Two additive, purely-informational surfaces, both scoped to coding-execution (Task/Bug) tickets only:

1. **Pre-flight estimate** — a token-count range shown on a not-yet-executed Task/Bug's detail screen and its Board card/list tile, calibrated via the same embedding-similarity "comparable historical tickets" mechanism `ai-assisted-complexity-and-estimate-suggestions` already built for complexity/estimate — but summing comparable tickets' actual `ticket_comment.inputTokens`/`outputTokens` (already persisted per `ai` comment, per `AgentDoneEvent`) instead of a complexity/estimate value. Shows "No estimate available" when no sufficiently comparable ticket exists yet (e.g. a fresh project) — no fabricated fallback number.
2. **Running total** — once a run is in flight, the same two surfaces (detail-screen execution banner, Board card/list tile) switch to a live-updating actual token total for the current run, reusing the `AgentToolUseEvent` live-progress channel `coding-execution-reliability-and-safety` already added.

Neither surface gates anything — `AutomationConfidence` and the existing reactive usage-window/overage handling (`providers.md`) are untouched.

## Open questions

- Exact granularity `AgentToolUseEvent` can report mid-turn: `ticket_comment.inputTokens`/`outputTokens` today are populated once, at turn completion (`AgentDoneEvent`) — whether `agent_bridge` can surface any live/partial usage figure during an in-flight turn (vs. the total only ticking up turn-by-turn/tool-call-boundary-by-boundary) is a real implementation unknown, left to `/propose` to investigate against the actual SDK/bridge surface.
- Exact comparable-ticket selection mechanics for cost specifically (same top-5/similarity-threshold/capable-tier defaults `ai-assisted-complexity-and-estimate-suggestions` uses, or its own tuned parameters) — left to `/propose`.
- Whether the Board-card token figure needs new visual real estate or can slot into `board-execution-indicators-and-notifications`' existing per-card indicator row — left to `/propose`/`/design-sync`.
- Whether a predicted range should ever be flagged low-confidence the way AI-suggested complexity/estimate already derives a deterministic low-confidence signal (e.g. very few/weakly-similar comparables) — not decided.

## Architectural implications

- Reuses `ai-assisted-complexity-and-estimate-suggestions`' embedding-similarity comparable-ticket search infrastructure (`TicketDocumentSearchService`) rather than building a second one — recalibrated against `ticket_comment.inputTokens`/`outputTokens` sums instead of complexity/estimate.
- No new schema needed for historical data — `inputTokens`/`outputTokens` are already persisted per `ai` comment (see `ticket_comment.dart`/`ticket_comment_model.dart`).
- Extends `board-execution-indicators-and-notifications`' existing per-card Board indicator (already built on `isExecuting`/`executionQueuePosition`/`executionAwaitingReview`/`executionFailureReason`) with a new token-figure element, covering both the pre-execution estimate and the in-flight running total.
- Running total requires wiring token-usage numbers through the `AgentToolUseEvent` live-progress channel (`coding-execution-reliability-and-safety`), which today drives only a one-line "Running `<tool>`..." hint — a new payload field, not a new event type, is the likely shape, but see Open questions.
- Deliberately does not touch `AutomationConfidence`, `ConsumptionSignal`, or the reactive usage-window/overage gate (`providers.md`) — stays purely additive/informational per this session's explicit no-gate decision.