---
ticketId: AIO-61
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-20T00:00:00.000
updatedAt: 2026-07-30T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Sequencing provider-configuration, sdd-workflow-in-ticket-system, and new-project-onboarding

## Key questions asked

1. Should sequencing optimize for fastest path to self-iteration, or overall product completeness treating all three explored ideas as equally near-term?
2. (Raised mid-session, resolved in `provider-configuration`'s own file) Given the watcher is dropped, can Claude Agent SDK alone cover everything for the desktop MVP?
3. Does a concrete 4-step order — provider-configuration, then a combined ticket-model foundation, then SDD-stage-triggering Execution, then new-project-onboarding's Inbox + attach flow — match, including combining the two ticket-model pieces into one change?

## Summary of answers

- Sequencing optimizes for **fastest path to self-iteration**, not even product completeness across the three explored ideas — confirmed implicitly by accepting an order that places the fully-explored Inbox/attach flow last, after the core self-iteration mechanism ships.
- `provider-configuration`'s simplification to Claude Agent SDK only (resolved separately, in that idea's own file) makes it the smallest and fastest of the three to build, reinforcing it as the clear starting point — it's also a hard prerequisite for every chat-based feature in the other two ideas.
- The final 4-step order was confirmed as-is, including combining `sdd-workflow-in-ticket-system`'s Foundation-phase ticket-model work with `new-project-onboarding`'s Release ticket type into a single change, since both are pure data-model/compatibility-matrix work with zero cross-dependency and no chat requirement.

## Conclusions reached

Build order, locked in:

1. **`provider-configuration`** — Claude Agent SDK only, unlocks every chat-based feature downstream.
2. **Combined ticket-model foundation** — new ideas/gaps ticket type, `specs/*.md`-as-Page-tickets, the Cubit-gated "current SDD stage" field (all from `sdd-workflow-in-ticket-system`), plus the new Release ticket type (from `new-project-onboarding`) — one change, since none of this needs a working provider and all of it is the same kind of compatibility-matrix/data-model work.
3. **SDD-stage-triggering Execution** — stage-triggering buttons, per-stage chat spawning/branching, reusing the `AutomationConfidence` type already built in step 1. This is the actual self-iteration mechanism: once shipped, Aion can drive its own further development through its own ticket-native workflow.
4. **`new-project-onboarding`'s Inbox + attach-to-existing-project flow** — real value, deliberately last since it's project-management convenience, not part of the critical path to self-iteration.

## Open questions

- Whether the "current SDD stage" field truly belongs in step 2 (built inert, ahead of any UI that uses it) or should move into step 3 alongside the stage-triggering UI that actually consumes it — a judgment call left for whoever writes step 2's `tasks.md`.
- Whether `new-project-onboarding`'s attach-to-existing-project flow specifically (which needs no provider at all — only its optional codebase-summarization sub-feature does) could be pulled forward ahead of step 4, since it's cheap and independent of the Inbox's chat-dependent pieces. Not decided; worth reconsidering once step 4 is actually reached.

## Architectural implications

- This ordering directly targets the "Aion iterates on itself" milestone as fast as possible — after step 3, Aion should be able to drive its own subsequent development (including steps 4 and beyond) through its own ticket-native SDD workflow rather than requiring the current CLI-driven `aion-arch/.claude/skills/` process.
- Once step 3 ships, the literal self-hosting transition point has been reached — later ideas (including this repo's own further brainstorming/proposing/applying) become candidates for running through Aion itself rather than through Claude Code Desktop against `aion-arch/`.

## Dogfood update (2026-07-23)

Ran the actual mechanism for the first time: created a Task ticket for a
real known gap, triggered coding execution via Aion's own UI, and let it
run to completion against the real `aion` repo (real branch, real push,
real PR — see `coding-execution-reliability-and-safety.md` for the full
findings). Conclusion: the mechanism *works* — this genuinely is Aion
driving its own development now — but it isn't safe to run unattended yet.
The most consequential finding wasn't a missing feature but a risk: the
coding-execution agent's own git operations can silently discard a
developer's uncommitted work sitting in the same tree, with no warning.
Treating that as resolved before leaning on this mechanism further seems
more important than moving on to step 4.