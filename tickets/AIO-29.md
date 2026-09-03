---
ticketId: AIO-29
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
# Design gate for the ticket-driven SDD workflow

## Key questions asked

1. Should the gate field live only on Story tickets (matching what `task-to-coding-execution-trigger` actually needs), or also on Epic tickets, which also carry `SddStage`?
2. Given `/design-sync` does real automated validation (Material-widget leakage, `AionColors` cross-referencing) via grep-based shell scripts with no obvious runtime equivalent — should the ticket-driven gate be a simple manual toggle, or does it need an in-app equivalent of that validation?
3. Should the design-gate concept be folded into the `SddStage` sequence itself (as new stage values, each spawning its own chat like every other stage), or kept as a separate parallel gate that only blocks Task execution without touching the stage stepper?
4. Where does the human's Claude Design export actually land — back into the `designBrief` chat as a reply, or a separate linked Page ticket mirroring `design.md`?
5. How does `designSync`'s validation get real file access, given every existing stage chat runs with `allowedTools: []` and plain-text-only context?
6. Does every Story pass through `designBrief`/`designSync` regardless of whether it touches UI, or does a non-UI Story skip both, mirroring `/propose`'s `PENDING`/`NOT REQUIRED` split?
7. If skipping is needed, is that determined automatically (inferred from the `proposed`-stage chat's own content) or via a manual toggle the user sets on the Story?

## Summary of answers

- **Scope:** a generic, nullable field pattern (like `TicketComplexity` — universal to every `TicketType`, meaningful only where applicable) rather than something structurally restricted at the type level, but its only real consumer today is `story` tickets — matching `sddStage`'s own "meaningless for every other `TicketType`" treatment. This is superseded in shape (see Conclusions) once folded into `SddStage` itself, but the underlying principle — universal field, story-only meaning — carries over to the new `needsDesignReview` determination described below.
- **We need the real design-sync phase**, not a rubber-stamp toggle — explicit rejection of the simple-manual-approval option.
- **Folded directly into the `SddStage` sequence**, not a parallel gate: `exploring → proposed → designBrief → designSync → verifying → archived`. Each new stage spawns its own chat via the existing `advanceSddStage` mechanism, exactly like every other stage transition.
- **The human's Claude Design export lands in a separate linked Page ticket**, mirroring `design.md` as its own artifact — not a reply inside the `designBrief` chat itself.
- **`designSync` gets a new read-only tool tier** — scoped file-read access only (no edit/git/bash/MCP), the first stage chat with any tool access at all. Confirmed as consistent with (not overlapping) `task-to-coding-execution-trigger`'s separate full tool-enabled tier for Task coding-execution — the two ideas each own one new, distinct tier: read-only here, full read/write there.
- **Non-UI Stories skip `designBrief`/`designSync` entirely**, advancing straight from `proposed` to `verifying` — mirroring `/propose`'s `PENDING`/`NOT REQUIRED` distinction.
- **The skip decision is automatic**, inferred from the `proposed`-stage chat's own content (what the decomposition actually produced), the same way `/propose` infers `PENDING` vs. `NOT REQUIRED` from the proposal's own file-touch scope — not a manual toggle.

## Conclusions reached

The design gate is not a bolt-on field — it's two new `SddStage` values:

`exploring → proposed → designBrief → designSync → verifying → archived`

- **`proposed → designBrief` (or `proposed → verifying` if skipped):** the `proposed`-stage chat itself determines, from its own decomposition content, whether the Story touches any UI — storing that determination (a `needsDesignReview`-shaped boolean, following the same universal-nullable-field pattern as `complexity`) so `advanceSddStage`'s precondition for this transition can branch on it automatically, no manual toggle.
- **`designBrief`:** spawns a chat reusing `/design-brief`'s existing prompt-generation logic (Story summary + Aion's design tokens), producing the copy-pasteable Claude Design prompt. No tools needed — pure text generation, same as every existing stage chat.
- **Human does the design work externally** in Claude Design, then pastes the result into a **new, separate linked Page ticket** (mirroring `design.md`, linked to the Story the same way Documentation pages already link to work tickets) — not back into the `designBrief` chat.
- **`designBrief → designSync`:** precondition is the linked design Page existing/populated (mirrors `advanceSddStage`'s existing "most recent chat has an AI reply" style preconditions, just checking a linked Page instead of a chat).
- **`designSync`:** spawns a chat with a **new read-only tool tier** — the agent can actually read source files (Non-Material-constraint leakage, `AionColors` cross-referencing) instead of reasoning from plain-text context alone, genuinely replicating `/design-sync`'s validation rather than rubber-stamping it.
- **`designSync → verifying`:** only advances once validation passes (mirrors `/design-sync` setting the CLI gate to `APPROVED` vs. leaving it `PENDING`).
- **Non-UI Stories skip `designBrief`/`designSync` entirely**, going straight from `proposed` to `verifying`.

Net effect for `task-to-coding-execution-trigger`: a Task's hard-block precondition ("Story's design gate must not be `PENDING`") becomes simply "the Story's `SddStage` must be at or past `verifying`" — no separate field to check, since a Story that needed design work can't reach `verifying` until `designSync` passed, and a Story that didn't need it skipped straight there anyway.

## Open questions

- Whether `advanceSddStage`'s existing 4-step UI tracker (`TicketDetailScreen`'s SDD-stage section, Explore/Propose/Verify/Archive nodes) needs to become a 6-step tracker unconditionally, or a variable-length one that collapses `designBrief`/`designSync` out of view for a Story that skipped them — left for `/propose`.
- How/when the linked design Page ticket itself gets created — automatically when `designBrief` starts (empty, waiting for paste), or manually by the user via the existing "+ New page" flow once they're ready to paste — not resolved this session.
- Exact mechanics of `designSync`'s read-only tool tier at the `agent_bridge`/`ClaudeAgentSdkClient` level (which `allowedTools` subset counts as "read-only") — an implementation detail for `/propose`, not decided here.

## Architectural implications

- Expands `SddStage` from 4 to 6 possible values (with 2 conditionally skippable) — the first change to that enum since it shipped in `sdd-ticket-execution`.
- Introduces the **first tool-access tier below full**: read-only, sitting between today's universal `allowedTools: []` and `task-to-coding-execution-trigger`'s full read/write tier. All three tiers now have a concrete owner across the two sibling ideas, with no overlap.
- Fully unblocks `task-to-coding-execution-trigger`'s design-gate precondition once shipped, by making "design gate `PENDING`" equivalent to "`SddStage` hasn't reached `verifying` yet" — no separate field needed on the consuming side.
- Self-contained: does not depend on `per-phase-tier-based-model-routing` (that idea is about model *selection* for these calls, not whether they run at all) — can `/propose` and ship independently.