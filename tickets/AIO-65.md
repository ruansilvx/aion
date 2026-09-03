---
ticketId: AIO-65
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
# Task-to-coding-execution trigger

## Key questions asked

1. Should Task→coding-execution reuse the same `AutomationConfidence` (auto/gated/manual) pattern already used for SDD-stage-triggering, or does handing an agent real file/git/bash access warrant a stricter, separate trigger?
2. Given Claude Agent SDK exposes no proactive budget query (only the reactive `AgentOverageDetectedEvent`), does "close to quota" mean relying on that reactive signal, or building the predictive "Budget gate" from project.md now?
3. What marks a Task ready for coding execution — plain `TicketStatus`, a new dedicated field (like `SddStage` but for Tasks), or a mix?
4. Does a Task queued behind an in-flight execution need a visible UI hint?
5. Should the run reuse the exact SDD-stage chat-spawning mechanism (spawned `chat` child, same streaming-comment UI), or does real tool output (diffs, bash, git) need a distinct execution-log presentation?
6. What happens on success (auto status flip?) and on failure (auto-escalation, per project.md's Orchestration pattern)?
7. Does completion-status handling follow `AutomationConfidence`, should "inReview" reflect an actually-opened PR, and is the design gate exempt from automation?
8. Grounding check: does a design-gate concept already exist in the ticket-driven `SddStage` workflow? (Verified: no — grep of tickets.md/providers.md found nothing; it exists only in the CLI `/propose`→`/design-sync`→`/apply` flow.)
9. Where does the design gate actually block — before `/apply` (i.e. before Task execution starts), not as an ongoing automation-level concern?
10. Should the two discovered prerequisites (design-gate porting, Tier/`ModelRouter`) be split into their own idea files, or folded into this one?

## Summary of answers

- **Trigger reuses the existing pattern, no new subsystem.** Same as `advanceSddStage`'s precondition-checked-on-screen-load approach — no new background daemon.
- **Budget override is reactive-only for now.** Once `AgentOverageDetectedEvent` fires, force every subsequent coding-execution trigger to `gated` (and inform the user) regardless of the configured `AutomationConfidence` level. The predictive, cost-estimate-based "Budget gate" from project.md §5 is explicitly deferred to a later idea.
- **Readiness signal is a mix.** Moving a Task to `inProgress` is the trigger (plain `TicketStatus`, no new field) — starting execution immediately if the single execution slot is free. Moving several Tasks to `inProgress` at once queues the rest (FIFO by move order) rather than running concurrently; true multi-line concurrent execution is flagged as a later improvement, not designed here.
- **Queued Tasks get a visible hint** (e.g. "Queued for execution — 2nd in line"), same spirit as `SddStageBlockReason`'s existing hint row.
- **Reuses the SDD-stage chat mechanism verbatim.** Spawns a `chat` child ticket under the Task, same streaming-comment UI as `advanceSddStage`'s spawned chats — the only change is that this call's `AgentModelClient` request runs with tools enabled, instead of the `allowedTools: []` every existing caller uses.
- **Completion follows `AutomationConfidence`.** Whether the Task's status auto-flips on success is gated by the same three-state (`auto|gated|manual`) pattern as SDD-stage advancement. On success, moving to `inReview` is meant to reflect that a PR has actually been opened as part of finishing the run — not just "the agent thinks it's done."
- **Failure: post results, no auto-escalation, no auto-retry** — consistent with `sdd-ticket-execution`'s precedent of dropping watcher/escalation machinery rather than build it with no concrete owner yet.
- **The design gate doesn't exist in the ticket-driven workflow today** — confirmed by grep, zero hits in tickets.md/providers.md. It's CLI-only (`proposal.md`'s own PENDING/NOT REQUIRED/APPROVED field, checked by `/apply`).
- **Once ported, the design gate is a hard precondition** blocking a Task from ever entering `inProgress` while its Story's design gate is `PENDING` — never subject to `AutomationConfidence`, unlike everything else in this flow. This corrects an earlier framing in-session that treated it as something `AutomationConfidence` needed to account for.
- **The standalone watcher persona stays dead** (already dropped by `sdd-ticket-execution`), but the Tier/`ModelRouter` concept (picking the cost-appropriate model per phase) is still wanted, for token-cost efficiency — fully unbuilt today per `providers.md`.
- **Design-gate porting and Tier/`ModelRouter` are split into their own idea files** rather than folded into this one, mirroring `self-iteration-sequencing.md`'s precedent of sequencing related-but-separable concerns as distinct changes.

## Conclusions reached

This idea is scoped narrowly to the execution-trigger mechanism itself, assuming its two prerequisites exist:

- Trigger: moving a Task to `inProgress` starts coding execution if the single execution slot is free; otherwise it queues FIFO, with a visible queue-position hint.
- Mechanism: reuses `advanceSddStage`'s exact chat-spawning pattern — spawned `chat` child, same streaming UI — just with tools enabled this time.
- Completion: gated by the existing `AutomationConfidence` level (auto/gated/manual) for whether status auto-flips to `inReview` on success; `inReview` is meant to reflect an actually-opened PR. Failure posts results in the chat with no auto-escalation/retry.
- Budget: reactive-only override via `AgentOverageDetectedEvent` forces `gated` near quota; predictive threshold deferred.
- Hard block (not automation-gated): a Task cannot enter `inProgress` while its Story's design gate is `PENDING`, once that gate exists on the ticket side.

Two hard prerequisites, split into their own idea files:
- [[design-gate-for-ticket-driven-sdd-workflow]] — porting the CLI's design-gate concept onto Story tickets.
- [[per-phase-tier-based-model-routing]] — reviving the Tier 1/2/3 `ModelRouter` concept for cost-appropriate model selection.

## Open questions

- True multi-line (concurrent) coding execution — explicitly deferred, not designed here.
- How "opening a PR" as part of a successful run actually works (branch naming, which repo, single-commit vs. incremental) — not covered this session, left for `/propose`.
- The predictive "Budget gate" (cost-estimate threshold, warn-before-limit) — deferred to a later idea/session.
- Whether this idea can `/propose` before its Tier/`ModelRouter` prerequisite ships (e.g. by using whichever model is globally configured until tiers exist), or must wait for both prerequisites — not resolved this session.

## Architectural implications

- Extends `AutomationConfidence` to a second real consumer beyond SDD-stage-triggering, reinforcing it as the shared automation pattern `project.md` §5 describes rather than a one-off.
- Hard-depends on [[design-gate-for-ticket-driven-sdd-workflow]] shipping first as a blocking precondition, and benefits from (but may not strictly require first) [[per-phase-tier-based-model-routing]] for model selection.
- Once built, this is the mechanism that closes the loop `self-iteration-sequencing.md` called "the literal self-hosting transition point" — actual code changes could then originate from a Task ticket via Aion's own ticket-native workflow, not just the conversational SDD-stage chats that ship today.