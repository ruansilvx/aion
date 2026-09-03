---
ticketId: AIO-30
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
# Reuse one coding-execution chat per Task instead of spawning a new one every trigger

## Key questions asked

1. Should Aion always reuse one single chat for a Task's entire execution
   lifecycle, or should some retriggers still start fresh (e.g. after a
   Task reaches done/cancelled and later reopens)?
2. How should the context-window cap that triggers a handoff be
   determined — the model's real limit, a user-configurable value, or
   both?
3. How should Aion actually measure usage against that cap, given no
   token-usage reporting exists in `agent_bridge/index.mjs` today?
4. When a handoff triggers, how should the new chat's opening context be
   assembled — a model-authored summary turn, or a programmatic one from
   git log/diff and status?
5. Should a handoff's new chat be distinguishable from the original (a
   different title + explicit link), or just another same-titled chat
   relying on creation-timestamp ordering?

## Summary of answers

1. **Ideally, always reuse** — one continuing chat regardless of how many
   attempts a Task takes. The one deliberate exception is nearing a
   context-window cap, not status history.
2. **Both — user cap defaults to the model's real limit.** Covers the
   common case automatically (derived from whatever `AgentModel` is
   configured for execution) while still letting the user set an earlier,
   more conservative threshold in Settings; can't be raised past the real
   model limit.
3. **Real reported token usage** — `agent_bridge/index.mjs` needs to
   start forwarding the Claude Agent SDK's own per-turn usage (input/
   output token counts, already present in the underlying API response)
   as a new event field. Aion sums these across the chat's turns for an
   accurate running total, rather than a character-count heuristic that
   could trigger too early or too late.
4. **Model-authored handoff turn** — mirrors this project's own
   `/handoff` skill: one final turn before the old chat closes out asks
   the model to write what's done, what's left, and key decisions/
   gotchas. Costs one extra turn but produces a genuinely useful, model-
   judged summary rather than raw git history.
5. **Distinct title + link back** — the new chat is titled "Coding
   Execution — <Task title> (continued)" (or similar) and linked to the
   original via `TicketLinkType.relatesTo`, so a human can tell them apart
   and navigate between them. The existing "most recently created" lookup
   (`_executionSucceededWithPr`) keeps working unchanged, since it doesn't
   key on title.

## Conclusions reached

- **Default behavior:** every `_triggerOrQueueCodingExecution` call
  (first trigger, `retryCodingExecution`, the toggle-status workaround)
  finds the Task's existing "Coding Execution — " chat (or its most
  recent "(continued)" descendant) and posts the new run's context/turns
  as additional comments on it. A brand-new chat is only created when none
  exists yet at all, or when a handoff fires.
- **Handoff trigger:** a per-chat running token total (summed from real
  usage the bridge now forwards per turn) compared against a cap — the
  configured `AgentModel`'s real context window by default, with a
  Settings field letting the user lower (never raise) it.
- **Handoff mechanics:** one final turn on the current chat asks the
  model to author a handoff summary; a new chat is created, titled with a
  "(continued)" suffix, linked back to the original via
  `TicketLinkType.relatesTo`, and seeded with that summary plus the usual
  Task title/description context. All subsequent turns for that Task go
  to the new chat until it, too, approaches the cap.

## Open questions

- Exact UI placement for the user-configurable context-cap Settings
  field — likely near the existing per-phase model config, but not
  walked through this session.
- Whether the handoff-summary turn should itself count toward the old
  chat's usage total in a way that could recursively trigger another
  handoff — an edge case not discussed, worth a sanity check in
  `/propose`'s design.md.
- Exact naming/numbering scheme if a Task needs a third, fourth, etc.
  continuation chat (e.g. "(continued 2)") — not walked through.

## Architectural implications

- `_runCodingExecution`'s chat-spawning logic changes from
  "always create" to "find-existing-or-create," directly affecting
  `_executionSucceededWithPr`'s and `getTicketById`'s existing lookups —
  both need to resolve the *chain* of original + continuation chats, not
  just "the most recently created 'Coding Execution — '-prefixed chat,"
  once continuations with a different title exist.
- Requires a new `agent_bridge/index.mjs` change (forwarding real
  per-turn token usage) — the first time the bridge reports anything
  usage-related beyond the existing reactive
  `AgentOverageDetectedEvent`(Pro/Max plan window, an unrelated concept).
- Reuses this repository's own `/handoff` skill pattern
  (`aion-arch/.claude/skills/handoff/`) as precedent for the
  model-authored summary turn — the same idea applied in-app to a
  coding-execution chat instead of a human/CLI session.
- Interacts with `board-execution-indicators-and-notifications`: that
  idea's Board "isExecuting" indicator and any failure/awaiting-review
  banner need to resolve against whichever chat in a Task's
  original+continuation chain is current, not assume a single fixed
  chat per Task.
- No change to `AutomationContext.codingExecution`/`codingExecutionRetry`
  gating — reuse vs. handoff is an orthogonal mechanics decision, the
  same relationship established for
  `board-execution-indicators-and-notifications`' backgrounding change.