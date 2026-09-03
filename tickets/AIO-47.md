---
ticketId: AIO-47
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-13T00:00:00.000
updatedAt: 2026-08-14T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Parallel Work

## Context: starting point

Opened directly against a Known gap already documented verbatim in
`aion-arch/specs/tickets.md`'s Known gaps section: coding execution "runs
one Task or Bug at a time, FIFO — no concurrent execution, and no way to
cancel a queued or in-flight run. The queue is in-memory only and does not
survive an app restart." That gap bundles three separable concerns —
concurrency, cancellation, restart-persistence — and this session was
explicitly asked to settle all three together, not scope one off.

## Key questions asked

1. Given worktree isolation already gives every run its own isolated git
   worktree, should Aion run multiple coding-execution runs truly in
   parallel, or keep the single-slot FIFO behavior and only fix
   cancellation/persistence around it?
2. What should bound the number of concurrent runs — a fixed constant, a
   user-configurable Settings field, or tied to the existing reactive
   budget/overage signal?
3. For the default ceiling itself (before any overage-driven cap-down),
   fixed constant or user-configurable?
4. Should coding-execution's cancel button build the shared
   `AgentModelClient`/`ChatCubit` cancellation plumbing
   `cancel-in-flight-agent-reply.md` already scoped generically (kill
   process, close stream, `cancelReply()`, stop button), subsuming that
   idea, or stay a narrow execution-only kill path?
5. When a user cancels a run (queued or in-flight), what happens to the
   Task/Bug's `TicketStatus`, which flips to `inProgress` the moment it's
   triggered/queued?
6. Should in-flight/queued execution state now be persisted so runs can
   genuinely resume after an app restart, or does the existing
   in-memory-only + orphaned/stalled-retry pattern stay as-is, just
   extended to N concurrent slots?

## Summary of answers

1. **True parallel runs.** Multiple Tasks/Bugs moved to `inProgress` each
   get their own concurrent run in their own worktree (already isolated),
   up to a limit — not single-slot FIFO anymore.
2. **Budget-aware cap**, layered on top of a baseline ceiling: the
   existing `AgentOverageDetectedEvent` reactive signal (already forces
   `gated` completion) additionally caps new concurrent starts down to 1
   for the rest of the session once overage is detected — reuses the
   existing signal rather than inventing a second one.
3. **User-configurable in Settings.** A new "Max concurrent coding
   executions" field, default a small number (e.g. 2), mirroring the
   context-window-cap precedent from
   `dont-spawn-new-chat-ticket-per-execution-trigger.md` — users can raise
   or lower it; the overage override still caps down to 1 regardless of
   the configured ceiling.
4. **Build the shared cancellation plumbing now (recommended and
   confirmed).** Real cancellation added to
   `AgentModelClient`/`ClaudeAgentSdkClient`/`ChatCubit` as this session's
   foundation — coding-execution's cancel button and a general chat
   stop-button both become thin callers of the same mechanism. This
   avoids building two separate cancellation mechanisms later (a narrow
   execution-only kill path now, then a second real one when
   `cancel-in-flight-agent-reply.md` eventually got built) that would need
   reconciling anyway. `cancel-in-flight-agent-reply.md`'s scope is fully
   absorbed here.
5. **Revert to prior status, keep artifacts, show partial-work
   indication.** Cancelling (queued or in-flight) reverts the ticket to
   whatever status it had immediately before the `inProgress` move.
   Any artifacts already created (worktree branch, commits) are kept, not
   discarded. The ticket carries a visible indication that some work was
   previously attempted/partially done, rather than looking untouched.
6. **Persist, and auto-resume gated by `AutomationConfidence`.** Queue and
   in-flight run state moves off pure in-memory `TicketsCubit` state onto
   real persistence. On relaunch, Aion detects persisted in-flight/queued
   runs and resumes them, gated by the existing three-state pattern:
   `auto` resumes automatically, `gated` asks the user before resuming
   each one, `manual` just surfaces them for the user to manually
   retrigger (reusing the same shape as coding-execution's existing
   verify-failure retry confidence, not a new bespoke flag).

## Conclusions reached

Settle all three strands of the Known gap together, as one change:

1. **True concurrency.** N coding-execution runs execute in parallel, each
   in its own already-isolated `git worktree`. Ceiling is a new
   user-configurable Settings field (default small, e.g. 2), additionally
   capped down to 1 for the rest of the session once
   `AgentOverageDetectedEvent` fires — reusing that existing reactive
   signal rather than a second budget mechanism.
2. **Shared cancellation plumbing.** A real cancellation handle threaded
   through `AgentModelClient` → `ClaudeAgentSdkClient` (kills the
   subprocess, closes the stream) → `ChatCubit.cancelReply()`, with a stop
   button in the transcript UI. Coding-execution's cancel action and a
   plain chat's stop button are both callers of this one mechanism. This
   fully subsumes and closes out `cancel-in-flight-agent-reply.md` — that
   idea's own scope ships as part of this change rather than separately.
3. **Cancel semantics.** Cancelling a queued run just removes it from the
   queue before a subprocess ever starts. Cancelling an in-flight run
   kills the subprocess via the mechanism above. Either way, the ticket
   reverts to its prior (pre-trigger) status, any artifacts already
   created are preserved (not deleted), and the ticket visibly indicates
   partial work was attempted — likely via the existing comment-thread
   mechanism (a system comment noting the cancellation and preserved
   branch), consistent with how execution failures are already surfaced.
4. **Real persistence + confidence-gated auto-resume.** Queue and
   in-flight execution state is persisted (not in-memory only) and
   survives an app restart. On relaunch, interrupted runs resume
   automatically (`auto`), only after user confirmation (`gated`), or
   stay surfaced for manual retrigger only (`manual`) — reusing
   `AutomationConfidence`'s existing three-state pattern rather than a new
   flag.

## Open questions

- Exact persistence storage shape for queue/in-flight state (a new Drift
  table is the likely shape, following existing conventions) — left for
  `/propose`'s design.md.
- How resumed runs reconcile with worktree state left over from before
  the restart — was the worktree/branch left in a state safe to resume
  from, or does resume always mean "start the implement turn over inside
  the existing worktree/branch"? Sharpens an open question already
  flagged in `coding-execution-reliability-and-safety.md` (large ignored
  directories/disk bloat per worktree), now more pressing with N
  simultaneous worktrees instead of one.
- Exact Settings UI placement/field name for "Max concurrent coding
  executions" — likely near the existing per-phase model config and the
  context-window-cap field, not walked through this session.
- Exact visual/badge treatment for the "had partial work done" indicator
  on a reverted ticket, and for the Board card once several tickets can
  show `isExecuting` simultaneously — a `design-brief`/`design-sync`
  question, not architectural.
- `board-execution-indicators-and-notifications.md` explicitly deferred
  building a persistent notification center "until Aion invests in
  parallel execution" — that condition is now met by this idea's
  conclusion, but building the notification center itself is not resolved
  here; flagged as a newly-relevant follow-up idea, not in scope.
- Whether a fourth `AutomationConfidence` consumer name is needed for
  resume-on-restart (e.g. `codingExecutionResume`) or whether it reuses
  the existing `codingExecutionRetry` confidence — left for `/propose`.

## Architectural implications

- `TicketsCubit._inFlightExecutionTaskId` generalizes from a single id to
  a set (N concurrent slots); `_executionQueue` now drains into however
  many slots are free instead of exactly one. `getTicketById`'s
  `isExecuting`/`executionQueuePosition` computations generalize
  accordingly — membership in the in-flight set vs. FIFO position for
  anything still queued beyond the ceiling.
- First time coding-execution's queue/in-flight state moves off pure
  in-memory `Cubit` state onto real persistence — a new category of
  storage for this subsystem, previously deliberately kept
  session-scoped.
- `AgentModelClient`'s interface shape changes again (a cancellation
  handle, alongside the `AgentToolUseEvent` addition from
  `coding-execution-reliability-and-safety.md`) — every current and
  future implementation (today: just `ClaudeAgentSdkClient`) needs to
  support both.
- Extends `AutomationConfidence` to a new consumer (resume-on-restart),
  reinforcing `project.md` §5's shared automation-confidence pattern
  rather than inventing a parallel flag.
- Fully subsumes and closes `cancel-in-flight-agent-reply.md` — its
  cancellation mechanism ships as part of this change; that idea file is
  marked superseded rather than staying open as separate future work.
- Makes `board-execution-indicators-and-notifications.md`'s explicitly
  deferred persistent notification center newly relevant (its stated
  precondition — parallel execution — is now being built), though
  building it is not part of this idea.
- Interacts with `board-execution-indicators-and-notifications.md`'s
  per-card `isExecuting` badge: needs to render correctly when several
  cards are simultaneously `isExecuting`, not just at most one — likely
  no data-model change (the per-ticket computed state already exists per
  ticket), but a visual case worth checking during `/propose`.

## Follow-up brainstorm session (2026-08-13) — scheduling mode, conflict avoidance, visual grouping

Raised directly by the user after the first session's conclusion: FIFO
vs. parallel should be user-facing and configurable (token-conscious users
may prefer FIFO), running work in parallel risks conflicts between
tickets that touch overlapping code, and a hybrid scheduling approach —
parallel by default, FIFO among tickets known to depend on one another,
visually grouped — could resolve both concerns at once.

### Grounding check

`tickets.md` already has a **blocked-dependency gate**: any ticket with
an unresolved `blocks`/`blockedBy` link is already rejected from moving
to `inProgress` at all until its blocker reaches `done`
(`_computeBlockedTicketIds`, drives the Board's existing `BlockedBadge`
from `board-task-ordering-indication.md`). Hard, explicitly-linked
dependencies are therefore *already* serialized today, for free — two
`blocks`-linked tickets can never both be in flight simultaneously
regardless of this idea. The real gap this session addresses is *softer*
dependency: tickets that aren't explicitly linked but are still likely to
conflict (e.g. siblings under the same Story), which the existing gate
doesn't cover.

### Key questions asked

1. Is last session's numeric concurrency ceiling (1 = FIFO) enough to
   satisfy "FIFO vs parallel configurable," or does the scheduling
   strategy need to be a distinct, named setting?
2. For Hybrid mode, what should count as a "known dependency" that forces
   two tickets to serialize even when concurrency slots are free —
   same-parent siblings, explicit `relatesTo` links, or both?
3. How should the Board visually group serialized siblings — a
   badge/tag, or physical clustering within their column?
4. In Hybrid mode, if the queue's front ticket is sibling-blocked by a
   running one but a later, non-conflicting queued ticket could start
   immediately, does the scheduler skip ahead to fill the free slot, or
   hold strict FIFO order and leave the slot idle?

### Summary of answers

1. **Explicit mode selector**, not just the ceiling. A new setting —
   "Coding execution scheduling": **Strict FIFO / Parallel / Hybrid
   (dependency-aware)** — carries scheduling intent as a first-class
   choice. The concurrency-ceiling field from the first session only
   applies/shows under Parallel and Hybrid.
2. **Same-parent siblings**, not explicit links. Tasks/Bugs sharing a
   parent Story are treated as likely to touch overlapping code and
   serialize against each other automatically — no new field on `Ticket`,
   reuses the existing hierarchy. (Explicit `blocks`/`blockedBy` links
   already hard-gate independently of scheduling mode, per the grounding
   check above; plain `relatesTo` links are not treated as a scheduling
   signal.)
3. **Physical clustering.** Within a status column, sibling cards are
   grouped adjacently (secondary sort key: `parentId`) rather than
   interleaved by other sort criteria — proximity itself communicates the
   relationship, no new badge.
4. **Skip-ahead scheduling.** When a free slot opens, the scheduler scans
   the queue for the next ticket not sibling-blocked by a currently
   running one and starts it, leaving the sibling-blocked ticket in its
   queue position. Maximizes actual use of the configured ceiling —
   holding a slot idle in front of unrelated available work would defeat
   Hybrid mode's own purpose.

### Conclusions reached

Extends (not replaces) the first session's conclusions:

- **Scheduling mode becomes a first-class setting**: Strict FIFO /
  Parallel / Hybrid, alongside the existing concurrency-ceiling field
  (shown only for Parallel/Hybrid). Strict FIFO behaves exactly like
  today's shipped single-slot queue.
- **Hybrid dependency signal is same-parent siblings only** — zero new
  data model, reuses `Ticket.parentId`. Explicit `blocks`/`blockedBy`
  links continue to hard-gate `inProgress` entirely, independent of
  scheduling mode; this idea doesn't change that gate.
- **Scheduler is skip-ahead, not strict-order-blocking** — a sibling-
  blocked ticket at the queue's front never stalls the whole queue while
  slots sit idle; the scheduler fills free slots with the next eligible
  ticket regardless of queue position, while preserving the sibling-
  blocked ticket's own relative position for when it does become
  eligible.
- **Board clusters siblings adjacently** within their column (secondary
  sort key `parentId`) rather than a new badge — needs reconciling with
  `board-task-ordering-indication.md`'s existing card-ordering/`blocked`
  badge concept during `/propose`, since both now touch board card
  ordering within a column.

### Open questions

- Exact interaction between sibling-cluster ordering (secondary sort:
  `parentId`) and any existing/future primary sort criteria on the Board
  — `board-task-ordering-indication.md` didn't establish a parent-based
  secondary sort, so this is new ordering logic, not a reuse — left for
  `/propose`.
- Whether switching scheduling mode mid-session (e.g. Strict FIFO →
  Parallel) while runs are already queued/in-flight needs any special
  reconciliation, or simply applies to scheduling decisions from that
  point forward — not discussed this session.
- Whether Hybrid's sibling-only signal should ever expand to
  grandchildren/deeper hierarchy (e.g. two Tasks under different Stories
  but the same Epic) — explicitly scoped to direct same-parent siblings
  only this session; not raised as insufficient, just not broadened.

### Architectural implications

- Scheduling mode is a new persisted setting (likely alongside the
  concurrency-ceiling field from the first session, same Settings area),
  read by the scheduler on every dequeue decision — `TicketsCubit`'s
  scheduling logic branches on mode (Strict FIFO: old single-slot
  behavior; Parallel: ceiling-only; Hybrid: ceiling + sibling-skip scan)
  rather than being one unconditional algorithm.
- The scheduler's dequeue step changes from "pop the front of
  `_executionQueue`" to a scan-for-next-eligible operation in
  Parallel/Hybrid modes — a real algorithmic change, not just a bigger
  ceiling number.
- Board card ordering gains a second influence (`parentId` clustering)
  alongside whatever `board-task-ordering-indication.md` and any future
  `board-task-ordering-indication`-adjacent sort control already
  establish — these need to compose, not conflict, during `/propose`.
- Confirms the blocked-dependency gate (`blocks`/`blockedBy`,
  `board-task-ordering-indication.md`) and this idea's Hybrid-mode
  sibling serialization are two independent mechanisms that both
  contribute to avoiding execution conflicts — the former a hard,
  explicit gate on `inProgress` itself; the latter a softer, automatic
  scheduling constraint. Neither subsumes the other.