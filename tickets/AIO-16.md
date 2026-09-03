---
ticketId: AIO-16
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-24T00:00:00.000
updatedAt: 2026-07-27T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Chat transcript UX redesign (Claude-Code-desktop-like)

**Archive note (2026-07-27):** only item (2) of the resolution above —
the visual paradigm (bubble for human, flat for AI, centered divider
for system) — shipped, via `chat-transcript-ux-redesign` (now
`changes/archive/`). Items (1) (persisting tool-use events as a new
structured, grouped comment shape) and (4) (moving designBrief/
designSync's long content into a linked Page + compact preview card)
were explicitly out of scope for that cycle (see its `proposal.md`
Non-goals — presentation-layer only, no `ChatCubit`/persistence
changes) and were never built. Item (3) (one live-updating component
serving both in-progress and settled turns) shipped only in the
narrower sense that already existed pre-cycle — `ChatState
.currentToolUse`/`streamingText` still drive a single `_StreamingBubble`
render path, now flat instead of bubbled, but no new persisted
tool-action structure backs it. Marking this idea archived because its
primary complaint (bubbles feeling wrong for an agentic context) is
resolved; items (1)/(4) remain real, unshipped scope if picked up
again later — start a fresh `/capture` or `/brainstorm` for them rather
than reopening this file.

## Key questions asked

1. Should tool-use events become part of the permanent chat record,
   instead of only driving a transient "Running `<tool>`..." hint that's
   lost once the run ends?
2. How should persisted tool-action entries be structured — a new
   comment shape reusing the existing pipeline, or a separate data
   model; and one row per tool call, or grouped per turn?
3. For long content (a big AI prose reply, or the system-context
   comment), should it collapse/truncate by default given "hard to
   identify what's useful" was the stated complaint?
4. (Follow-up on Q3's answer) Which specific long-content cases should
   move to a linked Page + compact preview/copy card — a general
   length-based rule, or the two named cases (designBrief's generated
   prompt, designSync's redundant page-content inlining) specifically?
5. How should the four content kinds render given "bubble for human, no
   bubble for agent" — specifically the system-context comment and the
   new grouped tool-action entries?
6. Should the live, in-progress view of a running turn use the exact
   same tool-action-group rendering as the final persisted version, or
   stay a separate simpler live-only indicator?

## Summary of answers

1. **Yes, persist structured tool-action entries** — a real, permanent
   action log (read/edit/run entries), not something only visible while
   a run is actively in progress.
2. **New comment shape, grouped per turn** — reuses the existing
   `TicketComment`/`CommentAuthorType` pipeline (same table, same
   git-projection/sync, same list rendering) rather than a parallel data
   model; one structured entry per model turn holding an ordered list of
   that turn's tool actions, not one row per individual tool call
   (avoids a wall of rows for a run touching many files).
3. **Show in full, no general truncation** — instead, adopt a
   Claude-Code-desktop-style visual paradigm (bubble for human, no
   bubble for agent "for the most part") as the primary scannability
   fix, with a narrower, scoped exception for known long-content cases
   (Q4) rather than a blanket collapse-by-default rule.
4. **Scoped to the named cases** — designBrief's generated Claude Design
   prompt (the AI's long output becomes a linked Page + compact
   preview/copy card, rather than a raw long `ai` bubble) and
   designSync's system-context comment (stop inlining the linked design
   Page's full content into the chat transcript — reference it
   compactly while still sending the actual content to the model behind
   the scenes). Not a general rule; other long AI replies elsewhere
   render in full.
5. **System: subtle inline divider, not a bubble** (it's Aion-assembled
   boilerplate, not something anyone "said," so it should recede rather
   than compete with the actual conversation). **Tool-action groups:
   flat, no bubble** — compact rows immediately preceding the agent's
   prose reply within the same turn, visually part of "what the agent
   did," not a separate message of its own.
6. **Yes, same rendering, live-updating** — the tool-action list looks
   identical whether the turn is still running or already finished; rows
   append live as `AgentToolUseEvent`s arrive, the last row shows a
   subtle active/pulse state while running, and once done it's simply
   the settled version of the same list, immediately followed by the
   agent's prose reply. One component serves both states.

## Conclusions reached

- **New persisted tool-action comment shape:** grouped per model turn,
  reusing the existing comment pipeline. Interleaved with that turn's
  actual prose reply as the durable, reviewable record of what the agent
  did — no longer dependent on the model's own prose to narrate its
  actions after the fact.
- **Visual paradigm:** human messages keep a bubble; agent prose and
  tool-action-group rows go flat/no-bubble; system-context comments
  render as a subtle divider-style block, visually receded from the
  actual conversation. (Exact colors/spacing/iconography deferred to
  `/design-brief` + Claude Design — this session resolved the structural
  "what gets a bubble" question, not the pixel-level styling.)
- **Live = final, same component:** the tool-action list is one
  live-updating component, not two separate live/settled renderings.
- **Two scoped long-content moves, not a general rule:**
  - `designBrief`'s AI-generated Claude Design prompt → a linked Page
    ticket + compact preview/copy card in the chat, instead of a raw
    long `ai` bubble.
  - `designSync`'s system-context comment → stop inlining the linked
    design Page's full content into the chat transcript's rendered text;
    reference it compactly instead (the model still receives the full
    content as part of its actual prompt — this is a rendering change,
    not a change to what the model sees).
  - Every other long AI reply elsewhere renders in full, unchanged.

## Open questions

- Exact new comment-shape schema for grouped tool-action entries (does
  it reuse `TicketComment` with a new nullable structured field, or a
  genuinely new `CommentAuthorType` value plus a separate payload type)
  — left for `/propose`'s design.md.
- Exact visual treatment (colors, spacing, iconography, exactly how
  "flat" the agent's text renders, exact divider styling for system
  comments) — a `/design-brief` → Claude Design → `/design-sync` question,
  not resolved here by design.
- Whether the compact preview/copy card pattern (for `designBrief`/
  `designSync`) is worth generalizing later if other long-content cases
  turn up — deliberately not generalized now (see Conclusions), but
  worth revisiting if a third case emerges.
- Exact expand/collapse or "open full page" interaction for the new
  preview/copy cards — implementation detail for `/propose`.

## Architectural implications

- `AgentToolUseEvent`'s data (currently `toolName`/`summary`, ephemeral
  only) needs to survive into persisted storage for the first time — a
  new consumer of `ChatCubit.runChatTurn`'s `onToolUse` callback that
  writes rather than just updates transient UI state.
- `CommentTile` (`ticket_detail_screen.dart`) — today a single widget
  handling `human`/`ai`/`system` uniformly as bordered bubbles — gets a
  significant restructure: per-author-type visual treatment diverges
  (bubble vs. flat vs. divider), plus a new tool-action-group rendering
  path entirely.
- This is a UI-touching change spanning every chat surface in the app
  (Task coding-execution chats, SDD-stage chats, and future Inbox
  chats) — `/propose`'s design gate will be `PENDING`, requiring the full
  `/design-brief` → Claude Design → `/design-sync` round-trip before
  `/apply`.
- `designBrief`/`designSync`'s existing linked-Page mechanism
  (`design-gate-for-ticket-driven-sdd-workflow`) gets a second use beyond
  "the human pastes their export here" — `designBrief`'s own generated
  output becomes page content too, making the Design page a two-way
  artifact (AI writes the prompt in, human's export follows) rather than
  human-write-only.
- Reinforces the "one component, two states (live/settled)" pattern also
  established in `board-execution-indicators-and-notifications`
  (`advanceSddStage` backgrounding) — both ideas favor a single
  rendering/mechanism that naturally spans in-progress and completed
  states, rather than a separate live-only affordance.