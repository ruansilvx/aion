---
ticketId: AIO-19
type: idea
status: backlog
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-27T00:00:00.000
updatedAt: 2026-08-31T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Confirm-decision tool for modelJudgment leaves

## Key questions asked

1. Concretely, what gap does prompt-surfaced-context-only leave open that a real round trip would close — the model silently under-weighing the criteria, wanting a structured recorded verdict instead of an inferred one, or both?
2. Given Aion's agentic loop already supports multiple tool calls within one turn, should "force weigh-in + structured verdict" be built as a new confirmation tool call the model makes within its normal flow (reusing existing infrastructure), or something that genuinely pauses and re-prompts outside the normal tool-calling loop?
3. If a new confirmation tool call exists, what happens when the model simply doesn't call it — declined by default (silence isn't approval, genuinely forces engagement) or fall back to proceed (today's unchanged safety net)?

## Summary of answers

- **Both** — the model silently under-weighing surfaced criteria, and wanting a structured, recorded verdict instead of one inferred from behavior, are both real gaps worth closing.
- **A normal tool call is enough** — reuse Aion's existing multi-tool-call-per-turn agentic loop. No new pause/resume infrastructure needed at all; this reframes the problem from "build new round-trip plumbing" to "add a new tool the model can call."
- **Fallback is "let the agent decide"** — explicitly not declined-by-default. The user reframed the whole question: this mechanism serves `AutomationConfidence.auto` specifically, and `auto`'s entire point is that the model should never pause or ask unless completely necessary. Forcing decline-by-default (or any hard requirement to call the new tool) would make `auto` behave like `gated` in disguise, defeating its purpose. The confirmation tool must be **available, not mandatory** — the model reaches for it only when it judges the situation genuinely calls for explicit reasoning; if it doesn't, behavior is byte-for-byte today's `modelJudgment` fallback (`proceed`).

## Conclusions reached

- **Mechanism: a new `confirm_decision`-shaped tool call**, exposed to the model only when a `modelJudgment` leaf is actually reached during decision-graph evaluation (scoped to that one call site's `AgentRequest.tools`, not globally available) — not a new pause/resume system. The model can call it within the same turn, using infrastructure that already exists (the multi-tool-call agentic loop every `onToolCall` handler already runs inside).
- **Never mandatory.** If the model doesn't call it, the outcome is unchanged from today's shipped `modelJudgment` behavior: proceed. This is the resolving insight of the session — the mechanism has to stay optional specifically *because* it serves `auto`, and `auto`'s defining property (per `AutomationConfidence`'s own doc comment — "applies the decision silently, no user interaction") is that it never pauses to ask unless the model itself decides that's warranted. A hard requirement to call the tool would quietly convert `auto` into `gated`.
- **When the model does call it**, the call itself is the "structured, recorded verdict" the user wanted — it naturally appears in the chat transcript as a normal tool call + result, no separate storage mechanism required for the recording half of the "both" answer.
- This is a genuine, if narrow, correction to `automation-decision-graphs`'s original Non-goal ("no real model-in-the-loop round trip... no mechanism anywhere pauses mid-tool-call") — not because that finding was wrong (it's still true that no pause/resume mechanism exists, and this idea doesn't build one), but because the round trip doesn't actually need pause/resume once reframed as an optional tool call inside the existing loop.

## Open questions

- **Tool-scoping mechanics.** Whether `AgentRequest.tools`/the `onToolCall` plumbing that already threads through each of `TicketsCubit`'s per-context handlers (`_handleCreateTicketToolCall`, etc. — see `automation-decision-graphs`'s design.md §4) actually supports exposing an *additional* tool conditionally, scoped to a single decision-graph evaluation, without leaking it into every other tool call in the same chat. Unexplored — flagged as `/explore`'s job.
- **What `confirm_decision`'s parameters actually are.** A rationale string is obvious; whether it also needs an explicit `proceed: bool` (letting the model use it to self-decline, not just self-confirm) is undesigned.
- **Where the verdict lives beyond the transcript.** The chat transcript naturally records the call, but whether anything else (a field on the ticket, an audit log) should also capture it for later review is unaddressed — deferred, not resolved either way.
- **UI surfacing.** Whether a `modelJudgment` node in the `GraphCanvas`/`DecisionOutlineList` editor (from `automation-decision-graphs`) should visually indicate "the model may call `confirm_decision` here" is a design-layer follow-up, not discussed this session.

## Architectural implications

- Extends [[automation-confidence-decisions]] (archived) rather than reopening any of its resolved calls — `AutomationConfidence`/`DecisionOutcome`/the strict-tree graph engine are all unchanged; this only fills in the previously-deferred `modelJudgment` mechanics.
- Reuses `TicketsCubit`'s existing per-context `onToolCall` dispatch and the underlying agentic multi-tool-call-per-turn loop (`AgentModelClient`/`AgentRequest`) — no new infrastructure category, unlike the `GraphCanvas` canvas primitive `automation-decision-graphs` had to build from scratch.
- Reinforces `AutomationConfidence.auto`'s existing contract (`core/automation/automation_confidence.dart`'s doc comment: "applies the decision silently, no user interaction") as a hard constraint on this mechanism's design, not just prose to keep in mind — the "never mandatory" conclusion is a direct consequence of taking that contract seriously.