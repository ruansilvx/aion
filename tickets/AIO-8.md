---
ticketId: AIO-8
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-04T00:00:00.000
updatedAt: 2026-08-20T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Automatic time tracking for tickets

## Key questions asked

1. Now that `addTimeSpent`/the `log_time` chat tool already exist for an AI
   agent to self-report time, is this idea still about a human-facing
   start/stop timer UI, or has the need shifted?
2. Is the remaining gap that the model's `log_time` `minutes` value is
   just a self-reported guess, and what's wanted is the system measuring
   real elapsed time itself?
3. What's the actual motivation — why does the recorded time matter?
4. Should automatic tracking be scoped to coding-execution runs only, or
   also cover plain advisory chat sessions with no coding execution?
5. How should a "session" be measured — agent-bridge process lifetime, or
   a chat's message-span (first to last message)?
6. What happens to the existing `log_time` tool call once automatic
   measurement exists — removed, or kept for gaps automatic measurement
   doesn't cover?
7. If `log_time` fires during a session the system is also
   auto-measuring, both add to `timeSpent` via the same additive
   `addTimeSpent` — is that acceptable double-counting, or should it be
   suppressed?

## Summary of answers

1. No — this was never about a human-facing timer. It was about the AI
   agent's own time logging, i.e. the same territory `log_time` already
   occupies.
2. Confirmed — the gap is that `log_time`'s `minutes` is model-guessed,
   not system-measured.
3. To build up trustworthy actuals data so a future calibration loop can
   compare predicted (`estimate`) vs. actual (`timeSpent`) and improve
   estimate suggestions for similar future tickets — directly building on
   the already-shipped [[ai-assisted-complexity-and-estimate-suggestions]],
   which today calibrates `estimate` against comparable historical
   tickets but has no feedback loop back from actuals.
4. Broad — every ticket the AI is involved with via chat, not just
   coding-execution runs. Accepted as inherently imprecise ("it might not
   be precise, since we can manually change tickets, but we can also
   have that info") rather than gated on precision.
5. Brainstormed as two-tier (bridge lifetime primary, message-span
   fallback) — **superseded by `/explore` findings below**, which found
   a single mechanism covers both cases without a fallback path.
6. Brainstormed as "kept, for gaps automatic measurement doesn't cover"
   — **superseded by `/explore` findings below**, which found no such
   gap actually exists in the current codebase.
7. Brainstormed as "suppress on overlap" — **superseded**: `/explore`
   found the overlap is total, not partial, which changes the answer
   from "suppress" to "remove the redundant source entirely."

## Conclusions reached

*(Revised after `/explore` — see findings below for the codebase grounding
that changed the two-tier design brainstormed initially.)*

Build automatic, system-measured time tracking for `Ticket.timeSpent` by
instrumenting the one chokepoint every AI turn already passes through,
replacing `log_time` rather than supplementing it:

- **Measurement point**: [ChatCubit.runChatTurn](../../aion/lib/features/tickets/presentation/cubit/chat_cubit.dart)
  — the single static method every AI turn funnels through (plain chat
  sends, `_runCodingExecution`'s implement/verify turns, stage chats,
  summarization). Record a wall-clock timestamp immediately before its
  `client.run()` call and again when the event stream truly completes
  (`ChatTurnSuccess`); the elapsed duration is the measured time for that
  turn. This works uniformly regardless of which `AgentModelClient`
  backs the call — no bridge-vs-non-bridge fork needed (see findings).
- **Scope**: every `runChatTurn` call whose chat has a resolvable parent
  ticket — covers both coding-execution and plain advisory chat turns,
  matching the "every ticket the AI touches" goal. Background,
  non-chat-attached model calls (e.g. `ticket_estimation_suggester.dart`'s
  direct `provider.client.run()` calls for AI-suggested complexity/
  estimate) are explicitly out of scope — that's inference work, not
  conversational work on behalf of a ticket, and has no chat ticket to
  attach a duration to in the first place.
- **Precision stance**: explicitly and permanently an approximation —
  wall-clock turn duration, not a precise effort measurement. Coexists
  with manual `timeSpent` edits via the same additive `addTimeSpent`
  path `log_time` already uses today.
- **`log_time` tool call**: **removed**, not kept. `/explore` found every
  `log_time` invocation happens strictly inside the same `client.run()`
  window automatic per-turn timing already measures (tool calls are only
  ever answered mid-stream, while that one process/call is still
  running) — so it is 100% redundant once automatic timing lands, not a
  partial-overlap case needing suppression logic. This reverses the
  brainstormed "keep log_time for gaps automatic measurement can't see"
  conclusion — no such gap exists in the current codebase.
- **Purpose**: build a trustworthy actuals dataset in `timeSpent` so a
  future estimate-calibration feedback loop (predicted vs. actual) can
  improve the AI-suggested `estimate` values that
  [[ai-assisted-complexity-and-estimate-suggestions]] already produces
  for comparable future tickets. That feedback loop itself is out of
  scope here — this idea only covers getting trustworthy actuals
  recorded.

## Explore findings

Investigated the actual call chain behind the brainstormed two-tier
design (bridge-lifetime + message-span fallback) and found it doesn't
match how the code is structured:

- **Two `AgentModelClient` implementations exist, and only one has a
  "bridge process."** `ClaudeAgentSdkClient` spawns a Node subprocess per
  `run()` call; `AnthropicMessagesApiProvider` wraps a plain HTTP client
  with no subprocess at all (`providers.md`'s "proven against two
  implementations" gap). So "agent-bridge lifetime" was never really a
  coding-execution-vs-chat distinction — it's a provider-implementation
  detail that doesn't exist for the second provider, which the
  brainstormed design didn't account for.
- **One chokepoint already exists.** `ChatCubit.runChatTurn` is the
  single call site every AI turn passes through — plain sends,
  coding-execution's implement/verify turns, stage chats, summarization
  — regardless of which client/provider is active underneath. Timing
  that one method directly gives real elapsed time uniformly for every
  turn, making the brainstormed bridge-lifetime/message-span split
  unnecessary — one instrumentation point replaces two.
- **`log_time`'s overlap with automatic timing is total, not partial.**
  Tool calls are only ever answered while the underlying `client.run()`
  call is still in flight (`_handleToolCallRequest` responds mid-stream,
  inside that same process/request). Since `log_time` can only fire from
  inside a `runChatTurn`-driven turn, every real invocation of it today
  is strictly contained within a window automatic timing will already
  measure — there is no scenario in the current codebase where
  `log_time` covers a gap automatic measurement misses. This is why the
  conclusion moved from "keep both, suppress on overlap" to "remove
  `log_time`, it's now dead weight."

## Open questions

- `runChatTurn` currently receives `chatTicketId` (where the AI comment
  is persisted) but not the parent ticket id `addTimeSpent` needs —
  today only the `log_time` handler resolves `chat.parentId` separately.
  Each of `runChatTurn`'s call sites (~6, across `chat_cubit.dart` and
  `tickets_cubit.dart`) will need that threaded through, or
  `runChatTurn` resolves it internally by loading the chat ticket. Left
  for `/propose` to design the exact parameter shape.
- Whether the UI should distinguish automatic vs. manual contributions
  to `timeSpent` (e.g. a breakdown) or just show one merged number, as
  it does today. Not discussed this session — this idea's original
  summary noted the current display is "manual entry only," so this
  likely touches `TicketMetadataSection`'s `InlineEditableField` and
  needs a design pass during `/propose`.
- Whether a turn that ends in `ChatTurnFailure`/`ChatTurnCancelled`
  should still log the partial elapsed time up to that point, or only
  `ChatTurnSuccess` turns count — not discussed this session.

## Architectural implications

- Touches [ChatCubit.runChatTurn](../../aion/lib/features/tickets/presentation/cubit/chat_cubit.dart)
  directly — new start/end timestamp capture around its `client.run()`
  call, and a new `addTimeSpent` call on success. Per
  [[feedback_cubit_domain_logic]], the decision of *which* ticket to log
  against and any related invariant logic belongs at the Cubit layer,
  not pushed into `ChatCubit`'s thin turn-running helper or the
  repository.
- Removes [logTimeToolDefinition](../../aion/lib/features/tickets/presentation/cubit/ticket_crud_tool_definitions.dart)
  and `TicketsCubit._handleLogTimeToolCall`, and drops `log_time` from
  the unconditional three-tool list `_toolsFor` appends to every chat —
  along with their existing test coverage in
  `tickets_cubit_ticket_crud_test.dart`.
- Interacts with the already-shipped
  [[estimate-timespent-rollup-for-ticket-hierarchy]] — automatic
  `timeSpent` contributions feed the same recompute walk as any other
  `timeSpent` write, no special-casing needed there since rollup already
  reads whatever value sits in `timeSpent` regardless of source.
- Long-term motivation ties to [[ai-assisted-complexity-and-estimate-suggestions]]
  (predicted-vs-actual calibration), though building that feedback loop
  itself is a separate, later idea — not in scope here.
- Coexists with manual `timeSpent` edits (existing
  `InlineEditableField`) — automatic contributions are additive via
  `addTimeSpent`, so manual edits and automatic measurement never
  clobber each other.
- Touches ticket detail screen if the open "breakdown vs. merged number"
  UI question resolves toward a breakdown — `/propose` should evaluate
  whether the design gate comes back `PENDING`.