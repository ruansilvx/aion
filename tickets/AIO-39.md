---
ticketId: AIO-39
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-12T00:00:00.000
updatedAt: 2026-08-12T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Mid-task/issue chat branching

## Key questions asked

1. What should trigger a branch — the user explicitly, or the AI recognizing and proposing it?
2. How should the AI actually signal "branch this" — a text-pattern marker (like Inbox's `RELEASE PLAN:` parsing) or real tool-calling?
3. Why is tool-calling disabled for chats outside coding execution in the first place?
4. Given real tool-calling is the direction: how much does the tool-calling layer need to support — fire-and-forget (model calls, app acts, turn ends) or genuine bidirectional (app executes, feeds result back, model keeps reasoning)?
5. Bidirectional tool-calling costs differ a lot by provider — ship on one provider first, or both from the start?
6. Can this be designed generically (one contract, provider-agnostic), or is it inherently provider-specific?
7. This breaks the "chat is a pure leaf" rule — should any chat be able to parent a chat (unbounded nesting), or should branching stay depth-capped?
8. project.md §2 says closing folds resolution into "the parent's documentation" — what does that mean for a chat ticket, which has no documentation field, only a comment transcript?
9. Symmetric question for closing: does the AI decide when to close (same gating as opening), or does closing stay a manual, human-only action?

## Summary of answers

1. AI-initiated: the model recognizes a blocking sub-issue and proposes branching; user confirms, or the AI handles it automatically, depending on `AutomationConfidence`.
2. Real tool-calling, not text-pattern parsing.
3. Two reasons: (a) the bridge (`agent_bridge/index.mjs`) is all-or-nothing — no scoped/read-only tier exists yet (`ToolAccessTier.readOnly` is declared but unimplemented, a separately tracked gap in `providers.md`); (b) most chat purposes are conversations *about* the project, not actions *on* it, so tool access defaults off per-purpose and only two callers (coding execution, full summarization/Q&A) override it, each wrapped in a throwaway worktree as an ad hoc safety net.
4. Bidirectional — the model needs to see the tool's result and keep reasoning in the same turn, not just fire an event and stop.
5. Ship both together, once the real cost split was clarified (see answer 6) — Messages API turned out to be the *easier* half, not the harder one.
6. Yes, generic at the app-facing contract level: extend `AgentRequest` with `tools: List<AgentToolDefinition>` and add a new non-terminal `AgentToolCallRequestEvent` to `AgentEvent`, with a way to feed a result back in. Messages API implements it via the standard, well-documented `tool_use`/`tool_result` multi-turn loop (an extra HTTP call with the result appended to history — no persistent connection needed). The Agent SDK/Node bridge path is the harder half: the bridge already runs its own tool loop *inside* Node for its native file/git/bash tools, but an app-defined tool like `branch_ticket` must execute in Dart (it needs `TicketsCubit`/the repository), so the bridge needs a new stdio round-trip per call — Node emits a "tool call request" NDJSON line, blocks, Dart replies with a "tool result" line, Node feeds it back into the SDK's continuing loop. One shared contract, two different translation layers underneath — same pattern `AgentModelClient` already uses for everything else.
7. Depth-capped: only a top-level chat (itself parented by a work-item ticket — an SDD-stage or coding-execution chat) can be branched. A branch chat stays a true leaf — no branch-of-a-branch, no unbounded nesting. Keeps rollup/leaf-detection logic handling one extra level, not arbitrary depth.
8. Yes — for a chat ticket, "fold into the parent's documentation" means the app posts a system-authored summary comment onto the *parent* chat's transcript once the branch closes, so the parent conversation visibly picks back up with the resolution folded in. Matches the existing pattern of system-authored comments (context assembly, failure banners) already used elsewhere in chat tickets — no new UI surface needed.
9. AI-initiated close, same `AutomationConfidence` gating as opening: the model inside the branch chat proposes/calls `close_branch` when it judges the sub-issue resolved, symmetric with how it proposes/calls `branch_ticket` to open one.

## Conclusions reached

Mid-task/issue chat branching is realized via a new generic, provider-agnostic bidirectional tool-calling layer added to the provider abstraction (`AgentModelClient`/`AgentRequest`/`AgentEvent`), not via text-pattern parsing. Two symmetric app-defined tools — `branch_ticket` and `close_branch` — are exposed to the model, both gated by the existing `AutomationConfidence` pattern (`auto`/`gated`/`manual`). This realizes project.md §2's Branch/Merge Semantics decision at the `chat`-ticket granularity: branching creates a child `chat` subticket (breaking the "chat is a pure leaf" rule, but depth-capped — a branch chat can't itself be branched); closing folds the resolution back into the parent chat as a system-authored summary comment, not a literal doc merge. Both providers (Claude Agent SDK bridge, Anthropic Messages API) implement the tool-calling contract together, since the relative cost turned out to favor Messages API (standard `tool_use`/`tool_result` loop) over the bridge (needs a new Node↔Dart stdio delegation round-trip for app-defined tools it can't execute itself).

## Open questions

- Migrating Release Planning's existing `RELEASE PLAN:` text-marker parsing onto this same tool-calling mechanism (flagged as inevitable but explicitly deferred — a separate follow-up, not part of this change).
- The exact UI for a `gated` branch/close proposal (inline confirm affordance in the chat transcript, most likely mirroring the existing Design Sync retry validation bar's placement) — left to `/design-brief` once this is proposed.
- Whether other app-defined tools beyond `branch_ticket`/`close_branch` should be designed alongside this (e.g. `create_release`, `link_ticket`) or added one at a time as their own changes once the tool-calling layer exists.
- Exact `AgentToolDefinition`/`AgentToolCallRequestEvent` field shapes, and the Node bridge's new NDJSON message types for the delegation round-trip — implementation detail for `/propose`'s `design.md`, not resolved here.

## Architectural implications

- Extends `AgentModelClient`/`AgentRequest`/`AgentEvent` (`providers.md`) with a new tool-calling axis, independent of `ToolAccessTier` (which stays about file/git/bash scope) — the first real change to that contract since `pluggable-provider-abstraction` shipped it.
- Requires the Node bridge (`agent_bridge/index.mjs`) to support delegating specific tool calls back to the Dart host process mid-run, rather than resolving every tool call in-process — new territory for that bridge.
- Breaks `TicketTypeHierarchy`'s current absolute rule that `resource`/`chat` "can never parent anything, including each other" (`tickets.md`) — `canParent`/`isAlwaysRoot` and leaf-detection (used by the estimate/timeSpent rollup and Board leaf-card rendering) all need a narrower, depth-aware notion of "leaf" instead of a flat type-based one.
- First concrete driver realizing project.md §2's Branch/Merge Semantics decision, previously stated only in the abstract with no ticket-type-specific mechanism.
- Sets a template other app-defined tools (`create_release`, etc.) can follow once built.