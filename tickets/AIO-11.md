---
ticketId: AIO-11
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-24T00:00:00.000
updatedAt: 2026-07-29T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Board execution/activity indicators and app-wide notifications

## Key questions asked

1. Should the Board card reuse the exact same states the Task-detail
   banner already computes, or does it need something coarser given
   limited card real estate?
2. Should this indicator cover only Task coding-execution (the only
   states that exist today), or also Epic/Story SDD-stage chats whenever
   one is actively running or waiting on the human?
3. For an SDD-stage chat, what should "waiting on human interaction"
   concretely mean, given `advanceSddStage`'s chat call is synchronous
   today (no background-running state exists for it, unlike coding
   execution)?
4. Should `advanceSddStage` convert to the same fire-and-forget pattern
   coding execution already uses (`unawaited(_runCodingExecution(task))`
   → an equivalent here), reusing that mechanism rather than building a
   separate one?
5. Should the in-app notification surface move to the
   persistent-navigation-shell level (app-wide), or should it be a
   persistent notification center instead of a toast?
6. Confirming: does making `advanceSddStage` non-blocking change only
   *how* the chat executes (backgrounded), leaving `AutomationContext.
   sddStage`'s existing auto/gated/manual trigger semantics (whether/when
   advancement happens) completely untouched?

## Summary of answers

1. **Same states, compact form** — reuse `isExecuting`/
   `executionQueuePosition`/`executionAwaitingReview`/
   `executionFailureReason` exactly, rendered as small icons/badges
   instead of the detail screen's full banner text. No new computation
   for the Task side, just a compact card presentation.
2. **All active chats** — not scoped to Task coding-execution alone.
   Epic/Story SDD-stage chats need the same at-a-glance board signal,
   even though (per Q3/Q4) that requires new state tracking that doesn't
   exist yet.
3. **The real ask surfaced here wasn't a data-modeling question but a UX
   one:** the user shouldn't have to sit on the ticket-detail screen
   waiting for a stage chat to finish — they should be free to check
   other tickets on the board or read Documentation in the meantime.
   Not (yet) asking for a standing background service — just that the
   UI stop blocking on it.
4. **Yes** — reuse the exact same fire-and-forget mechanism, rather than
   inventing a second one. One background-execution pattern serves both
   Task coding-execution and Epic/Story stage-advancement.
5. **Shell-level toast, for now** — relocate today's
   `TicketsErrorReason` toast listening from the Board/Task-detail
   screens up to `WorkspaceNavShell`, reusing the existing `AppToast`
   widget, so it fires regardless of which top-level section is active.
   A persistent notification center is real future value, but explicitly
   deferred until Aion invests in parallel execution — with only a
   single-slot FIFO queue today (one coding-execution run in flight at a
   time), a missed toast is recoverable by just opening the Task; a
   history matters more once multiple runs can be in flight
   simultaneously.
6. **Yes, exactly** — backgrounding is purely an execution-mechanics
   change (unawaited instead of awaited), orthogonal to
   `AutomationContext.sddStage`'s trigger-confidence gate. Same
   relationship coding execution already has: `AutomationContext.
   codingExecution`/`codingExecutionRetry` gate *whether/when* different
   decisions happen, but the run itself is already unawaited regardless
   of the configured confidence. No change to when/whether a stage
   advances — only to whether the UI blocks while it does.

## Conclusions reached

- **Board card indicator:** a compact per-card badge/icon reusing
  `isExecuting`/`executionQueuePosition`/`executionAwaitingReview`/
  `executionFailureReason` for Tasks, plus a new equivalent set of states
  for Epic/Story SDD-stage chats (see below) — running / awaiting human /
  failed, at minimum.
- **`advanceSddStage` becomes fire-and-forget:** converted to the same
  `unawaited(...)` pattern `_runCodingExecution` already uses. The stage
  transition still persists immediately; the chat spawn + first AI turn
  runs in the background. A new computed state (working title
  `isAdvancingStage`) drives both the Board indicator and a
  Task-detail-equivalent banner for Epics/Stories, mirroring
  `isExecuting`'s existing shape.
- **`AutomationContext.sddStage`'s auto/gated/manual semantics are
  untouched** — this change only affects execution mechanics
  (awaited → backgrounded), never whether/when a stage advances.
- **In-app notifications:** relocate the existing `TicketsErrorReason`
  toast `BlocListener` from the Board/Task-detail screens to
  `WorkspaceNavShell`, so it fires app-wide (Documentation, Settings, the
  future Inbox included) rather than only when already viewing Board or
  a Task's detail screen. Still a transient toast, not a history.
- **Persistent notification center:** explicitly deferred, not
  unraised — worth building once Aion invests in parallel execution
  (multiple simultaneous runs), not before.

## Open questions

- Exact new state names/shape for the SDD-stage-chat equivalent of
  `isExecuting`/`executionAwaitingReview`/`executionFailureReason` — left
  for `/propose`'s design.md, following `getTicketById`'s existing
  computation pattern as closely as possible.
- Exact compact visual treatment for the Board card (icon set, badge
  placement) — a `design-brief`/`design-sync` question, not architectural.
- Whether stage-chat failure needs its own retry semantics analogous to
  coding execution's verify-gate retry, or whether a failed/stalled stage
  chat just surfaces via the same failure-banner shape with manual retry
  only — not raised this session, left for `/propose`.

## Architectural implications

- Extends `TicketsCubit`'s existing background-execution pattern (today
  exclusively `_runCodingExecution`) to a second consumer
  (`advanceSddStage`) — both funnel through the same
  unawaited-plus-computed-state shape, rather than staying two divergent
  mechanisms.
- `getTicketById`'s per-ticket computed-state additions grow beyond Task
  tickets for the first time — Epic/Story tickets get their own
  execution-adjacent computed states, previously a Task-only concept.
- The Board (`TicketBoardCard`/`_CardVisual`) gains its first
  execution-state-aware rendering — previously purely
  ticket-field-driven (title/status/priority), now also reflecting live
  `TicketsCubit` state.
- Moves toast-listening ownership from per-screen `BlocListener`s
  (Board, Task-detail) to `WorkspaceNavShell` — every current and future
  `/workspace/*` screen inherits app-wide notification coverage for free,
  rather than each new screen needing its own listener.
- Deliberately leaves `AutomationContext`/`AutomationConfidence` and
  `AutomationSettingsRepository` completely unchanged — no new context,
  no new persisted setting — this idea is additive UI/mechanics only.
- A persistent notification center, when eventually built, would likely
  need a real `Notification` entity (read/unread, per-event) — explicitly
  out of scope for now, noted as a natural sequel once parallel execution
  exists.