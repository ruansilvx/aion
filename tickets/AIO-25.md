---
ticketId: AIO-25
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-14T00:00:00.000
updatedAt: 2026-07-17T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Define type-compatibility matrix

## Key questions asked

1. What's the actual pain point — a bad UI case, or wanting the model locked down before the app grows?
2. Which ticket types need to be covered — just today's set, or upcoming ones too?
3. Can epic parent any other type, or only some?
4. Should story be allowed to parent another story (nested stories)?
5. Should task be allowed to parent another task (subtasks), and should story be allowed to parent task?
6. Should resource/page/chat ever have children, or are they always leaves?
7. Can resource/page/chat be parented by any work type, or only by epic?

## Summary of answers

- Motivation is proactive: lock down the domain model before more ticket types/features make retrofitting painful, not just a one-off UI fix.
- Scope is the current six types from `tickets.md` (`epic | story | task | resource | page | chat`); future types are out of scope for this pass.
- Looked at prior art: classic Jira uses a fixed shallow hierarchy (Epic → Story/Task/Bug → Subtask, no same-type nesting); Linear/Asana/ClickUp allow arbitrarily deep same-type nesting. Aion follows the Jira-style fixed-hierarchy approach rather than open-ended nesting.
- Epic can parent anything except another epic.
- Story can be parented only by epic; story→story is blocked (same-type relationships go through linking instead of parenting).
- Story can parent task; task→task nesting is blocked (avoids task becoming an ad-hoc story-breakdown mechanism).
- resource/page/chat are always leaf nodes — never have children, regardless of type. Relationships between them happen only via linking, not parenting.
- Any work type (epic, story, or task) can parent a resource/page/chat directly — not restricted to epic-only attachment.

## Conclusions reached

A strict, non-configurable hierarchy:

| Parent \ Child | epic | story | task | resource | page | chat |
|---|---|---|---|---|---|---|
| **epic** | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **story** | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ |
| **task** | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ |
| **resource** | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **page** | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **chat** | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |

In words: epic > story > task is a strict work-breakdown chain with no same-type nesting at any level; resource/page/chat are leaf attachments parentable by any work type (epic/story/task) but never able to parent anything themselves. Same-type relationships (story-to-story, task-to-task) are expressed via linking, not parenting.

This is a small, additive rule — no new types, no configurability. Ready for `/propose`.

## Open questions

- Whether the matrix should be a hardcoded constant/lookup table or something more data-driven — deferred to `/propose`/`/design.md`, since it's a small enough rule set that hardcoding is likely sufficient, but worth a deliberate call during proposal rather than assumed here.
- Whether a violation should be prevented proactively (invalid parent candidates simply don't appear in `TicketParentPicker`) versus caught reactively (blocked with an error on attempted reparent) — likely "both, UI filters + Cubit validates," consistent with existing Cubit-level domain-logic convention, but left for `/propose` to spell out precisely.

## Architectural implications

- `TicketsCubit.getValidParentCandidates` needs a type-compatibility check added alongside its existing self-parent/cycle checks — this is exactly the known gap flagged in `tickets.md`.
- `TicketParentPicker`'s candidate list must respect the same rule so the UI never offers a structurally invalid parent.
- Per existing project convention, this validation belongs in the Cubit layer, not pushed down into the repository.
- No schema/migration impact — `TicketType` enum is unchanged; this is pure validation logic layered on existing reparenting.