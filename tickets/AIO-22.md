---
ticketId: AIO-22
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-28T00:00:00.000
updatedAt: 2026-08-31T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Decision graph agentJudgment condition

## Key questions asked

1. Is a guaranteed, Dart-forced answer actually the right bar for `agentJudgment` — worth paying for a genuine second, independent `AgentModelClient.run()` per evaluation — or would a best-effort mechanism (offered as an available tool before the gated call, model answers only if it judges it warranted, falls back to a default branch otherwise) be an acceptable trade, even though it can no longer guarantee the graph author's branch gets followed?
2. In the best-effort shape, when the model doesn't answer (not offered the tool that turn, or offered but declined to call it) — does the graph treat that silence as the `unmatched` branch (mirroring `confirm_decision`'s "let the agent decide" precedent, no forced default), or does "unanswered" need its own distinct fallback (e.g. always `gated`, kept separate from a genuine "the model said no")?

## Summary of answers

- **Best-effort seems more reasonable — unless the second-spawn cost can actually be avoided.** Not a flat preference for best-effort: the user's answer is explicitly conditional on whether a cheaper alternative to a full fresh spawn exists. This reframed the session from "pick one" to "the real fork is a technical unknown, and the design should be conditional on its answer."
- **Mirror the `confirm_decision` precedent exactly: let the agent decide, silence falls through to `unmatched`.** No forced `gated` default for "unanswered" — consistent with `auto`'s "never pause unless the model itself judges it necessary" contract, which `confirm-decision-tool-for-modeljudgment-leaves` already established as a hard constraint on any mechanism serving `auto`.

## Conclusions reached

- **The design is conditional on one unresolved technical fact**, not a single fixed shape:
  1. **If cheap session resumption is available** (the Claude Agent SDK's `query()`, or `AgentModelClient`/`agent_bridge` built to expose it, can continue an existing conversation thread rather than fully reconstructing context) — build `agentJudgment` as a genuine, Dart-forced round-trip: the graph evaluator awaits a scoped yes/no answer and deterministically follows `matchedBranch`/`unmatchedBranch`, at low marginal cost since most context is already loaded/cached in the resumed thread. This restores this idea's original guaranteed-branching promise from the first `pluggable-decision-graph-conditions` session.
  2. **If it isn't available** (every call genuinely requires a fresh bridge-process spawn with full context reconstruction) — build `agentJudgment` as best-effort: exposed as an available tool to the model *before* it calls the gated tool (e.g. `create_ticket`), so the model can proactively call it within its own existing turn if it judges the situation warrants explicit reasoning — never a Dart-forced follow-up. If the model doesn't call it, the node resolves to `unmatched` (mirroring `confirm_decision`'s precedent), same as `modelJudgment`'s existing prompt-surfaced-only fallback today.
- **The best-effort variant and `confirm_decision` are the same mechanism.** Both: a tool offered to the model before a gated action, called only if the model itself decides to, silent-defaults-to-proceed-equivalent on non-use. The only difference is that `agentJudgment`'s best-effort form additionally uses the model's answer to pick a real graph branch, where `confirm_decision` was purely a recorded rationale with no routing effect. This is additive, not a separate mechanism — `confirm-decision-tool-for-modeljudgment-leaves`'s "superseded by pluggable-decision-graph-conditions" framing (written before this correction existed) is wrong in direction: it isn't superseded, it's the ancestor of this file's best-effort branch and should be treated as converging with it, not replaced by it.
- **Whichever variant ships, the node-visual-differentiation open question from the original session still applies** — a best-effort `agentJudgment` node is still worth badging distinctly in `GraphCanvas`/`DecisionOutlineList` (it may silently do nothing if the model never calls the tool), just as a guaranteed round-trip node would be badged for its cost/latency.

## Open questions

- **The core technical unknown itself.** Whether `AgentModelClient`/`agent_bridge`, or the Claude Agent SDK's `query()` underneath it, actually supports resuming/continuing an existing conversation thread cheaply — this is the entire fork this session couldn't resolve by reasoning alone. Explicitly deferred to `/explore`.
- **If resumable: what "cheap" actually means in practice.** Even a resumed thread might not be free — token cost for the follow-up exchange, added latency inside an already-latency-sensitive tool-call-blocked flow, and whether resumption is available uniformly across `AgentProvider` implementations or only the Claude Agent SDK one (per [[pluggable-provider-abstraction]] territory) are all unexplored.
- **If not resumable: how a best-effort tool is scoped per node.** `confirm-decision-tool-for-modeljudgment-leaves`'s own open question ("whether `AgentRequest.tools`/`onToolCall` plumbing supports exposing a tool conditionally, scoped to one decision-graph evaluation, without leaking into every other tool call in the same chat") applies identically here and was never resolved either.
- **What happens to `DecisionOutcome.modelJudgment` (the existing shipped outcome value) once `agentJudgment` (a condition, not an outcome) exists in either form.** Not discussed this session — worth checking whether the outcome value becomes redundant once a real condition kind can do the same job with an actual branch.

## Architectural implications

- Directly continues [[pluggable-decision-graph-conditions]] (archived) as its excluded Phase B — that file's `next_action` explicitly called for this.
- **Corrects [[confirm-decision-tool-for-modeljudgment-leaves]]'s status** from "superseded" to "pending convergence, contingent on this file's resume-feasibility `/explore`" — that file's own mechanism is this file's best-effort fallback design, not a discarded alternative.
- Whichever variant ships, it finally implements the round-trip [[automation-confidence-decisions]] flagged as a real integration gap ("no mechanism anywhere pauses mid-tool-call to ask the model a follow-up and resume") — the guaranteed variant closes it directly; the best-effort variant closes it exactly as `confirm-decision-tool-for-modeljudgment-leaves` originally proposed (reframing "pause and resume" as "an optional tool call within the existing loop").
- If resumption is found feasible, it likely also benefits other unrelated future work needing cheaper mid-flow model consultation — worth flagging to whoever runs the `/explore` pass, even though this idea only needs it for one purpose.