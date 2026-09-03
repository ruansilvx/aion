---
ticketId: AIO-48
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-21T00:00:00.000
updatedAt: 2026-07-22T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Per-phase/tier-based model routing (ModelRouter revival)

## Key questions asked

1. Can per-phase model selection deliver real value while only Claude Agent SDK (3 models: Opus 4.8/Sonnet 5/Haiku 4.5) is configurable, or does it need multi-provider support first to matter?
2. Should assignment be per literal SDD stage (up to 7 dropdowns) or bucketed into a small number of tiers, and should a chat visibly show which model handled it?
3. Should the tier buckets reuse the tool-access split (no-tools/read-only/full) that the sibling ideas already established, or track a separate reasoning-weight axis?
4. Given the concrete stage list (`exploring, proposed, designBrief, designSync, verifying, archived` + Task coding-execution), how should they map onto project.md's original Frontier/Capable/Execution tiers?
5. Does this replace Settings' existing single global model dropdown outright with tier dropdowns, or stay a simple-mode ("planning"/"execution model") toggle with per-phase detail hidden behind an advanced toggle, per project.md's original sketch?

## Summary of answers

- **Single-provider now, no redesign needed later.** Ships scoped to Claude Agent SDK's 3 models; once multi-provider support exists, a tier can freely mix any provider/model combination without restructuring this idea's mechanism.
- **Bucketed into a small number of tiers**, not one dropdown per literal stage. Each chat visibly shows which model handled it (extends `CommentTile`'s existing "via `<model>`" line — shown always, not just for AI comments as it is today).
- **Tiers track a reasoning-weight axis, independent of tool access.** The tool-access split (no-tools/read-only/full, established by `design-gate-for-ticket-driven-sdd-workflow` and `task-to-coding-execution-trigger`) is a separate, orthogonal concern — a stage's tier is about how much reasoning the job needs, not what it's permitted to touch.
- **Concrete mapping confirmed:**
  - **Frontier** — `exploring`, `proposed`, `verifying` (epic/story-level judgment calls).
  - **Capable** — `designBrief`, `designSync`, `archived` (comparatively mechanical: prompt generation, checklist-style validation, doc updates).
  - **Execution** — Task coding-execution.
- **Settings replaces the single global model dropdown outright** with three tier dropdowns (Frontier/Capable/Execution) — no simple/advanced toggle distinction; each defaults to whatever model was previously globally selected, populated from the single configured provider's models.

## Conclusions reached

Ships as: a `ModelPhase`-shaped tier enum (`frontier | capable | execution`), each phase's call sites mapped per the confirmed split above, and a "Settings → Models" section with three model dropdowns replacing today's single global one — all sourced from whichever provider(s) are configured (today, only Claude Agent SDK's 3 models). Every spawned chat displays which model actually handled it, regardless of author type. This is scoped to selection/routing only — it does not itself add new providers; multi-provider support remains its own unbuilt prerequisite for genuinely mixed-provider tier assignment, but this mechanism needs no rework once that exists.

## Open questions

- Exact `ModelPhase`/`ModelRouter` type shape and how `AgentRequest` carries phase information to the resolver — implementation detail for `/propose`.
- Whether a future "manual override" concept (project.md's original Tier 2 framing included this) is needed per-ticket/per-chat, overriding its tier's default model for one run — not raised or resolved this session.
- Whether/how a fourth tier is ever needed once mobile/web on-device (`flutter_local_ai`) models enter the picture — out of scope here (desktop-only concern today).

## Follow-up decisions (2026-07-22)

- **Live model discovery is real, but not a drop-in.** Grounded while
  `/propose`-ing `task-to-coding-execution-trigger`: `agent_model.dart`'s
  comment claiming "Claude Agent SDK has no equivalent endpoint" is
  outdated. The installed SDK
  (`aion/agent_bridge/node_modules/@anthropic-ai/claude-agent-sdk`) exposes
  `Query.supportedModels(): Promise<ModelInfo[]>`
  (`{value, displayName, description}`) on the object `query()` returns.
  However, that method — like `setModel`/`setPermissionMode`/
  `mcpServerStatus` — is a control-request method, documented as "only
  supported when streaming input/output is used." Today's
  `agent_bridge/index.mjs` calls `query({prompt: string, options})`
  (one-shot string prompt, fresh process per call) — the non-streaming
  mode this method doesn't work in. Actually fetching the live list would
  mean restructuring the bridge's per-call invocation to streaming-input
  mode (`prompt: AsyncIterable<SDKUserMessage>`) — a real architectural
  change to how every call is made, not a one-line swap of the hardcoded
  `AgentModel` enum for a fetch. Whether that restructuring is worth it
  (vs. keeping the enum hand-maintained, matching Ollama's already-planned
  live `/api/tags` fetch only for that provider) is an open call for
  whoever `/propose`s this idea.

## Architectural implications

- Fully independent axis from the tool-access tiers (no-tools/read-only/full) established across `design-gate-for-ticket-driven-sdd-workflow` and `task-to-coding-execution-trigger` — a stage's tool access and its model tier are set separately.
- References `designBrief`/`designSync` (from `design-gate-for-ticket-driven-sdd-workflow`, not yet shipped) and Task coding-execution (from `task-to-coding-execution-trigger`, not yet shipped) in its tier mapping, but doesn't hard-block on either shipping first — the Frontier/Capable tiers already have real, shipped consumers (`exploring`/`proposed`/`verifying`/`archived`), so this can `/propose` and ship now, with the remaining tier slots wired in as those sibling ideas land. Mirrors `AutomationConfidence` shipping in `provider-configuration` ahead of `sdd-ticket-execution`, its later real consumer.
- Once all three ideas (this one, the design gate, and the coding-execution trigger) ship, `task-to-coding-execution-trigger` gets real model-tier routing for its execution calls rather than reusing whatever model the conversational stages use — closing the last piece project.md §5 envisioned for the desktop MVP.