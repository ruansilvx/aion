---
ticketId: AIO-74
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-26T00:00:00.000
updatedAt: 2026-09-01T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Verify-stage has no quality gate before archiving

The verifying → archived SDD-stage transition has no content quality
gate. `TicketsCubit.advanceSddStage`'s precondition for that
transition is just "the Verify-stage chat's most recent comment is
AI-authored" (`aion-arch/specs/tickets.md:1968-1970`), unlike
`designSync → verifying` which hard-requires a literal
`DESIGN GATE: APPROVED` line in the chat reply
(`tickets.md:1989-1996`). There's no equivalent
"VERIFIED"/no-CRITICAL-findings marker gating advancement to
`archived` — a ticket can advance even if the Verify-stage chat's
prose reports CRITICAL issues.

This means the CLI `/archive` skill's rule ("only archive a change
that has been through `/verify` with no outstanding CRITICAL
findings", `aion-arch-workflow.md`) has no enforcement counterpart in
the ticket-native SDD workflow.

## Key questions asked

1. Should the gate mirror `designSync` exactly (a self-attested
   `VERIFY GATE: APPROVED`/`PENDING` line), or should it require the
   model to machine-parseably report a findings count instead of
   trusting a bare word choice?
2. Given `AutomationConfidence` already gates every `advanceSddStage`
   transition uniformly at the UI layer (auto/gated/manual —
   `tickets.md:4962-4979`), separate from `designSync`'s own hard
   content precondition — should the verify gate reuse that existing
   machinery, or does it need its own bespoke confidence-aware logic?
3. After a `VERIFY GATE: PENDING` verdict, where does the actual code
   fix happen before re-verifying — there's no equivalent to
   `designSync`'s "edit the linked design Page" artifact?
4. Once fix Tasks/Bugs reach `done`, does re-verification fire
   automatically (mirroring `designSync → verifying`'s "Tasks done"
   precondition check, `tickets.md:1992`) or always require a manual
   tap (mirroring `retryDesignSync`'s manual-only retry,
   `tickets.md:2120`, and the stage-advance-failure banner,
   `tickets.md:4957-4959`)?

## Summary of answers

1. Mirror `designSync` exactly — a self-attested `VERIFY GATE:
   APPROVED`/`PENDING` line, not a machine-parsed findings count.
2. Reuse the existing `AutomationConfidence`-driven UI
   (`canAdvanceSddStage` + auto/gated/manual) rather than building new
   confidence-specific gating logic — the same combo every other SDD
   transition already uses.
3. PENDING findings route back through coding execution: new or
   existing Task/Bug children get the fix, mirroring how the CLI
   `/verify` skill's findings "route back to `/apply`"
   (`aion-arch-workflow.md`).
4. Automatic once those fix Tasks reach `done`-role status — no
   separate manual retry step — but still subject to
   `AutomationConfidence`: `auto` fires the re-verify chat turn
   immediately, `gated` surfaces a confirm banner, `manual` shows a
   plain button, exactly as `canAdvanceSddStage` + `AutomationConfidence`
   already behave for every other transition.

## Conclusions reached

Add a `VERIFY GATE: APPROVED`/`PENDING` literal-marker precondition to
`verifying → archived`, checked via a new `_verifyApproved` helper
mirroring `_designSyncApproved`. On `PENDING`, the ticket stays
blocked at `verifying`; CRITICAL findings materialize as new or reuse
existing Task/Bug children for a fresh coding-execution pass. Once
every such fix Task/Bug reaches `done`-role status, the precondition
re-evaluates automatically (no bespoke `retryVerify` needed, unlike
`retryDesignSync`'s manual-only re-check) and the existing
`canAdvanceSddStage` + `AutomationConfidence` combo takes over exactly
as it already does for every other SDD-stage transition — no new
automation-confidence-specific machinery required anywhere in this
change.

## Open questions

- How does a `PENDING` verdict concretely link its CRITICAL findings
  to specific new/existing Task/Bug children — does the model's reply
  need a structured block (like `proposed`'s `## Decomposition`
  fence) for `TicketsCubit` to parse and materialize, or is that
  linkage left to a human reading the chat and creating/editing Tasks
  by hand?
- Should `sddStageBlockReason`/the SDD-stage section's footer surface
  the `PENDING` verdict's reasoning directly (mirroring the
  stage-advance-failure banner's scrollable reason well,
  `tickets.md:5023-5034`), or just a generic "Verification pending —
  fix Tasks required" hint?
- Does this apply retroactively to any ticket already sitting at
  `verifying` when the change ships, or only to future stage entries?

## Architectural implications

- Requires a new `_verifyApproved` precondition check in
  `TicketsCubit.advanceSddStage`'s `verifying → archived` branch,
  parallel to `_designSyncApproved`.
- Requires the `verifying`-stage chat's assembled context
  (`_assembleStageContext`) to request the reply end with the
  `VERIFY GATE: APPROVED`/`PENDING` line, mirroring `designSync`'s
  context-assembly addition (`tickets.md:2046-2049`).
- Likely requires a "Tasks done" style precondition analogous to
  `designSync → verifying`'s child-Tasks-done check
  (`tickets.md:1992`), scoped to whichever fix Task/Bug children get
  attached to a `PENDING` verdict.
- No changes needed to `AutomationConfidenceRepository`/
  `AutomationSettingsRepository` (`providers.md`) — this reuses the
  existing per-`AutomationContext` confidence machinery rather than
  adding a new context or value.
- Should reconcile with [[sdd-workflow-in-ticket-system]] (the
  ticket-native SDD workflow this gate lives inside) and
  [[automation-confidence-decisions]] (still open on whether
  "confidence" ever means a computed score rather than the existing
  user-set enum — this idea's conclusion assumes the existing
  user-set `AutomationConfidence` enum, not a computed one).