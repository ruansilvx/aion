---
ticketId: AIO-50
type: idea
status: done
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
# Pluggable decision graph conditions

## Key questions asked

1. When you say "create conditions," do you mean a project/user should be able to define a genuinely new condition type themselves from the UI (real pluggability, no code), or do you just want more built-in condition types available to wire up, especially for the six contexts that currently have nothing in the picker at all?
2. For a no-code user-defined condition, which shape matches what you're picturing — a pick-a-field/pick-an-operator rule builder over an exposed vocabulary, or a written expression/formula?
3. (User-raised) Since Aion already runs an agent, can't conditions just be arbitrary — e.g. "if task is too big, then split into two" — evaluated by the model itself rather than by a fixed vocabulary or formula language?
4. Given a free-text/model-evaluated condition can't hard-override deterministically without new plumbing, do you want a real round-trip (the model answers yes/no, Dart routes the branch deterministically on that answer) or an advisory-only shape (the condition text just gets folded into the prompt, like today's `modelJudgment`, with no enforced branch)?
5. (User asked for tradeoffs, not just a choice) What are the pros and cons of the round-trip vs. advisory-only shapes?
6. (Reframed by user) The graph exists for genuine judgment calls the agent needs to make in `auto` mode — e.g. two warnings and one critical verify finding: fix critical only, fix everything, or fix warnings only if not expensive? What do you recommend?
7. Does a deterministic rule-builder (for the parts of a judgment call that are actually checkable in code, like finding severity) plus `agentJudgment` (for the genuinely subjective parts, like "is this expensive") match what you're picturing, with catalog conditions staying instant/deterministic and only `agentJudgment` paying for a round-trip?
8. But what if the user wants to change/add to the *deterministic* part too, not just get an `agentJudgment` escape hatch — should Aion also build a deterministic rule-builder so simple no-judgment-needed conditions stay instant and hard-override-capable, or is paying a round-trip for every user-defined condition (however trivial) an acceptable tradeoff to avoid building the rule-builder/field-vocabulary work?
9. Given you lean toward building the rule-builder too, can deterministic and non-deterministic (`agentJudgment`) conditions coexist freely within the same decision graph/tree?
10. Should a user-defined condition (rule-builder or `agentJudgment`) be a reusable, named definition — shown in the picker for reuse across other nodes/graphs like Aion's own catalog entries — or a one-off, inline definition authored fresh each time it's added to a node?

## Summary of answers

- **(a) — real pluggability, no code.** Not just surfacing more Aion-authored catalog entries; a project should be able to define genuinely new condition types itself.
- **Neither rule-builder nor formula, initially** — the user's own reframe (question 3) preempted this fork by proposing conditions be evaluated by the agent itself rather than authored as a fixed vocabulary or expression language.
- **Arbitrary, agent-evaluated conditions**, explicitly motivated by "since we're using agents" — free natural-language conditions like "if task is too big, then split into two," not bounded by a pre-defined field vocabulary.
- **Real round-trip, not advisory-only** — implied by the follow-up framing (the user wants enforcement — the split to actually happen — not just guidance the model may ignore); confirmed by the user wanting genuine judgment-call decisions ("fix critical only? fix everything? fix warnings only if not expensive?") to actually route the graph, not merely inform the model.
- **Recommended and accepted: a hybrid** — deterministic rule-builder for anything checkable in code (e.g. finding severity), `agentJudgment` (free-text, round-trip-evaluated) only for the genuinely subjective remainder (e.g. "is this fix expensive"). Catalog/rule-builder conditions stay instant and hard-override-capable; only `agentJudgment` leaves pay for a live model call.
- **User leans toward building the deterministic rule-builder too** — not content to let `agentJudgment` be the only pluggable mechanism, specifically to keep simple/no-judgment-needed conditions instant and deterministic rather than forcing every user-defined check through a round-trip.
- **Yes, deterministic and non-deterministic conditions can coexist in the same graph**, mixed freely node by node — confirmed as architecturally sound given `DecisionNode`'s existing shape (`conditionId`/`conditionParams` + matched/unmatched branches to other nodes) doesn't assume every condition resolves through the same evaluator path.
- **Not reusable — inline, one-off definitions per node**, not a shared named catalog. ("I don't think so" to the reusability question.)

## Conclusions reached

- **Two new condition kinds, additive to today's Aion-authored catalog, freely mixable in one strict-tree graph:**
  1. **Deterministic rule-builder** — field + operator + value, project-defined, no code, evaluated synchronously, retains full hard-override capability exactly like today's `attemptExceedsMax`/`sessionOverageDetected` catalog entries.
  2. **`agentJudgment`** — a free-text prompt (e.g. "is this fix expensive?") resolved via a genuine round-trip: the model answers a scoped yes/no, and Dart deterministically follows `matchedBranch`/`unmatchedBranch` on that answer — not the advisory-only, prompt-surfaced-only shape `DecisionOutcome.modelJudgment` uses today.
- **`evaluateDecisionGraph` moves from pure/synchronous to conditionally-async** — the top-level walk API needs to support awaiting since any node might be an `agentJudgment` kind, but a path through the tree that never touches one stays fully synchronous in practice; the cost is per-path, not per-tree.
- **`agentJudgment` round-trips should reuse the live coding-execution session already in flight**, not spin up a separately-primed model call — the incremental cost is one small yes/no exchange inside an existing turn (findings/context already loaded), not a fresh context load. This is the working assumption; `/explore` should confirm the concrete mechanics.
- **`agentJudgment` round-trip failures default to `gated`** (pause for human confirmation) rather than guessing — consistent with the project's existing "ask the human when unsure" pattern (the existing `gated` pause mechanism).
- **Match outcomes are not limited to today's four `DecisionOutcome` values (`proceed`/`gated`/`decline`/`modelJudgment`).** A match can invoke a named skill via the already-shipped Phase 2 skill-attachment mechanism (`configurable-workflow-and-automation-engine`) — this is what makes an outcome like "split into two" expressible at all, rather than forcing every node's outcome into the existing enum.
- **User-defined conditions of either kind are authored inline, per node** — no shared, named, reusable custom-condition library; duplicate authoring across nodes/graphs is an accepted tradeoff for a simpler data model and UI.
- **Field vocabulary for the rule-builder should grow incrementally, context by context, as real cases come up** — not a big-bang effort to instrument all 8 `AutomationContext` values' `DecisionEvalContext` up front. Today, only 2 of 8 contexts (`codingExecutionRetry`, `codingExecution`) have any signals instrumented at all.
- **This is `configurable-workflow-and-automation-engine`'s Phase 3**, scoped specifically to the decision-graph half of that shared engine (per `automation-confidence-decisions`' explore finding that the transition-precondition half and the `AutomationContext` decision-graph half share structure/evaluator/storage but not node content) — not a reopening of either archived idea, but the concrete unbuilt-scope follow-on both of them pointed at.

## /explore findings (2026-08-27)

Investigated ahead of `/propose`; two open questions below are resolved,
one working assumption is corrected:

- **Async migration blast radius: negligible, not open.** `TicketsCubit
  ._evaluateDecisionGraph` is already `async` today and every one of its
  ~9 call sites already `await`s it — it's a thin wrapper around the
  pure sync `evaluateDecisionGraph`. The one caller that touches the
  pure function directly (`ticket_detail_screen.dart`) already sits
  inside an async `.then()` chain. Making `evaluateDecisionGraph` itself
  conditionally-async (for `agentJudgment`, Phase B) is mechanical.
- **Field vocabulary gap: confirmed exactly as stated.** `DecisionEvalContext`
  has exactly two fields (`attempt`, `sessionOverageDetected`), covering
  2 of 8 `AutomationContext` values. No surprises.
- **`agentJudgment`'s "reuse the live session" assumption does not hold
  — corrects this file's Conclusions/Open-questions sections above.**
  `AgentModelClient`/`AgentRequest` has no session/resume concept at
  all; every `run()` is a fresh bridge-process spawn. Worse, the
  contexts you'd actually want `agentJudgment` for (`ticketCreation`,
  `ticketLinking`, `chatBranching`) call `_evaluateDecisionGraph` from
  *inside* a tool-call handler, while the model is already blocked
  awaiting that tool call's own result — there's no in-flight moment to
  slip a fresh yes/no question into the same turn. A real round-trip
  can only be a **second, independent `AgentModelClient.run()` call**
  (a small self-contained scoped-yes/no prompt) made before resolving
  the outer tool call — genuinely new context, not a free piggyback.
  This also means `agentJudgment` may end up needing the same
  tool-call-based mechanism [[confirm-decision-tool-for-modeljudgment-leaves]]
  proposed, just packaged differently — the "supersedes" call in this
  file's Architectural implications section deserves a second look once
  Phase B is actually designed, not assumed settled.
- **Recommendation (accepted):** split into two `/propose` cycles rather
  than one large one. Phase A — deterministic rule-builder — is
  self-contained (additive to the existing catalog/evaluator pattern,
  no new I/O boundary) and specced as [[decision-graph-rule-builder]].
  Phase B — `agentJudgment` — waits for a dedicated round-trip-mechanic
  design pass, informed by the correction above.

## Open questions

- **Field vocabulary per context.** What's actually exposable/inspectable for the rule-builder in each of the 8 contexts — needs real investigation, not just decision. Most contexts (`sddStage`, `ticketCreation`, `ticketLinking`, `codingExecutionResume`, `specAutoLink`, `chatBranching`) have zero `DecisionEvalContext` signals today.
- **`agentJudgment` round-trip mechanics.** "Reuse the live session" is the working assumption, not a confirmed design — how the round-trip actually threads through `TicketsCubit`'s existing tool-call interception points, whether every one of the 8 contexts even has a "live session" to piggyback on at the moment a decision graph is consulted, and what the actual prompt/response contract looks like for a scoped yes/no ask, are all unexplored.
- **`evaluateDecisionGraph`'s async migration blast radius.** Every current caller assumes a pure, synchronous function — which call sites need to change, and whether any of them are themselves synchronous in a way that makes awaiting awkward, is unexplored.
- **Rule-builder UI shape.** Not designed at all — how a user picks a field, operator, and value in `DecisionGraphEditorScreen`'s existing "+ Add condition" flow, and how that flow visually distinguishes a deterministic pick from an `agentJudgment` free-text entry, is open.
- **Visual differentiation of node kinds, beyond just the authoring flow.** (Raised post-session.) Once a graph mixes catalog/rule-builder nodes (instant, deterministic) with `agentJudgment` nodes (live model call on every evaluation, non-deterministic), both `GraphCanvas` and the synced `DecisionOutlineList` need to make that distinction visible at a glance for *existing* nodes already in the tree, not just at creation time — a user scanning a graph should be able to tell which paths are free/instant and which paths cost a round-trip without opening each node. Candidate direction: a per-node badge/icon plus an "info" affordance surfacing something like "this node calls the model — may be slower/costlier to evaluate." Not designed — left to `/propose`.
- **Skill-attachment-as-outcome mechanics.** Composing Phase 2's skill attachment as a node outcome (rather than the four fixed `DecisionOutcome` values) was asserted as the way to express actions like "split into two," but the actual data-model change to `DecisionBranch`/`DecisionOutcome` to support it hasn't been designed.

## Architectural implications

- Directly continues [[configurable-workflow-and-automation-engine]]'s Phase 3 (pluggable gate behaviors) and [[automation-confidence-decisions]]'s explore finding that the decision-graph engine's structure/evaluator/storage is shared but node catalogs are not — this idea's rule-builder and `agentJudgment` kinds are new node *content*, layered onto the already-shipped graph structure (`DecisionNode`, `DecisionBranch`, strict-tree invariant, `DecisionGraphConfigCubit`) without changing it.
- Turns `evaluateDecisionGraph` from a pure function into one with a real I/O boundary — a first for that function, and worth flagging to whoever picks up `/explore` since "pure, no I/O" was an explicit, deliberate property of the original design.
- Extends `DecisionEvalContext` non-trivially — today it's populated ad hoc, per call site, with only what two existing conditions need. A real rule-builder vocabulary means most of the 8 `AutomationContext` call sites need new instrumentation work they don't have today.
- Gives Phase 2's skill-attachment mechanism ([[configurable-workflow-and-automation-engine]]) a second consumer beyond status/stage triggers — a decision-graph node match becoming a skill invocation, not just a `DecisionOutcome`.
- **Supersedes [[confirm-decision-tool-for-modeljudgment-leaves]]** (2026-08-27 follow-up, post-persist). That idea's `confirm_decision` tool — an optional, runtime-model-decided call to record a verdict at a `modelJudgment` leaf, built specifically to avoid needing round-trip plumbing — is strictly dominated once `agentJudgment` exists: same in-session cost profile, a guaranteed rather than optional verdict, and a no-op-branch pattern (`matchedBranch`/`unmatchedBranch` both leading to the same terminal) reproduces that idea's exact "record-only" case through this one mechanism. That file is marked superseded, not deleted, per this project's idea-file convention.

_Related idea not migrated (no corresponding ticket): decision-graph-rule-builder._