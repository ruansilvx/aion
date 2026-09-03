---
ticketId: AIO-26
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-08T00:00:00.000
updatedAt: 2026-08-20T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Delegate ticket CRUD to Aion during coding execution

## Key questions asked

1. (Follow-up, mid-session on a different idea, 2026-08-08) Does the coding-execution model create ticket files itself, and could ticket CRUD be delegated to Aion instead?
2. (2026-08-20, continuation) What ticket operations would a coding-execution run actually want mid-task?
3. Should this be a structured reply-block (decomposition's pattern) or a real tool call the model invokes mid-turn?
4. Should ticket-CRUD tool calls require human confirmation, inherit the run's `AutomationConfidence` wholesale, or depend on which operation it is?
5. Where's the auto-apply/gated line across the four candidate operations?
6. Does this stay scoped to coding execution, or generalize to SDD-stage chats too?

## Summary of answers

- (2026-08-08) Grounded the current state: the model has **no functioning path** to create/edit/delete `epic`/`story`/`task`/`bug`/`chat` tickets via file writes today — those types project one-way (`TicketGitProjector.project`), never read back into the DB. Only `page`/`resource` tickets are live bidirectional files, and that path is for human editing, not model-CRUD. Decomposition's structured `## Decomposition`-block-parsed-after-the-turn pattern was the only existing "model proposes, Aion materializes" precedent at that time.
- (2026-08-20) All four candidate operations — spin off a follow-up ticket, add a `TicketLink`, flag a possible duplicate, log time — were confirmed as reasonable without narrowing; they're not mutually exclusive, so scope stayed at "all four."
- Mechanism resolved as a **real tool call**, not a reply-block: coding execution already has a tool-call loop (file/git/bash tools), so ticket-CRUD tools are just more entries on that same surface, letting the model get a result back mid-task rather than finding out next turn.
- This surfaced a stronger precedent than decomposition: **mid-task chat branching is already shipped** using exactly this shape — `branch_ticket`/`close_branch` tool calls, dispatched through `ChatCubit`/`TicketsCubit._handleBranchToolCall`/`_handleCloseBranchToolCall`, materializing real ticket-graph writes without the model ever touching the DB directly. This is the pattern to generalize, not decomposition's.
- Guardrails resolved as per-operation, not a single fixed rule: **low-consequence operations auto-apply; medium-to-high-consequence operations follow whatever `AutomationConfidence` tier already governs the run** (auto/gated/manual) rather than always requiring confirmation. Concretely: `log_time` (additive, low-consequence) auto-applies unconditionally; `create_ticket` and `add_link` (permanently reshape the graph — new entities/relationships someone triages later) and `flag_duplicate` follow the run's existing confidence tier.
- Scope confirmed as **not coding-execution-only**: `providers.md`/`tickets.md` confirm `AgentRequest.tools`/`onToolCall` is already a generic axis used by every chat-with-tools surface (SDD-stage chats included), not something coding execution owns exclusively. So the new tools are available anywhere that surface is already wired, without a separate mechanism per chat type.

## Conclusions reached

Generalize the existing `branch_ticket`/`close_branch` tool-call precedent (mid-task chat branching, already shipped) with four new ticket-CRUD tools — `create_ticket`, `add_link`, `flag_duplicate`, `log_time` — dispatched via the same `AgentRequest.tools`/`onToolCall` → `TicketsCubit`-style handler pattern. Not decomposition's parse-after-the-fact pattern, and not scoped to coding execution alone — available to any chat surface that already wires `tools`/`onToolCall`. Guardrail: `log_time` always auto-applies; `create_ticket`/`add_link`/`flag_duplicate` follow the run's existing `AutomationConfidence` tier rather than a new fixed gate. Direction is clear enough for `/propose`.

## Open questions

- Does `flag_duplicate` actually write a `duplicates`/`duplicatedBy` `TicketLink`, or just surface a chat-visible signal for a human to act on? Left for `/propose`-level design, not resolved here.
- Exact tool argument schemas for each of the four tools (`/propose`-level detail).
- How `flag_duplicate` interacts with the embedding-based duplicate-detection idea from the same original session — still treated as a separate concern per [[ticket-graph-and-embedding-context-enrichment]] (that idea is about context flowing *into* a run; this one is ticket-graph changes flowing *out*), but the exact hand-off between "embedding search surfaces a likely duplicate" and "model calls `flag_duplicate`" isn't designed yet.

## Architectural implications

- Generalizes mid-task chat branching's `branch_ticket`/`close_branch` tool-call-and-dispatch pattern (not decomposition's) into a reusable shape for more ticket-graph operations — likely a shared dispatch helper alongside `_handleBranchToolCall`/`_handleCloseBranchToolCall` in `TicketsCubit`/`ChatCubit`.
- Confirms `TicketGitProjector`'s one-way nature is a hard constraint any CRUD-delegation design must respect — it cannot be the delegation channel itself, only ever a read-only side effect of Aion's own writes.
- Reuses `AutomationConfidence` as the sole gating dial for `create_ticket`/`add_link`/`flag_duplicate` — no new confidence/permission concept needed, but `log_time` is a documented exception that bypasses it.
- Confirms `AgentRequest.tools`/`onToolCall` (see `providers.md`) is the right generic layer to extend — this idea adds tool *definitions*, not new plumbing, since SDD-stage chats and coding execution already share the mechanism.
- Related to [[ticket-graph-and-embedding-context-enrichment]] — that idea handles context flowing *into* a run; this one is about ticket-graph changes flowing *out* of a run.
- Related to [[mid-task-chat-branching]] — the shipped precedent this idea generalizes from.