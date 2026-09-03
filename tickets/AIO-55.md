---
ticketId: AIO-55
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-20T00:00:00.000
updatedAt: 2026-07-20T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Provider configuration (Claude Agent SDK only)

## Key questions asked

1. Given the goal of reaching self-iteration fastest, should the first version of provider config support the full six-provider list from project.md day one, or just the two that unblock everything else (Anthropic API + Claude Agent SDK)?
2. Do those two leverage the user's existing Claude Pro plan? Would there be any other cost?
3. Given the user has been using Claude Code Desktop for every step of the SDD cycle already, can Claude Agent SDK replace the Messages API too?
4. Given a very limited budget, is there a token/cost projection for using only Agent SDK versus a mix of Agent SDK + Messages API?
5. Given the tight budget, should the budget-gate/automation-confidence consent system be built in the first pass rather than deferred?
6. (Follow-up, during cross-idea sequencing) Given the standalone watcher concept was dropped entirely (see `sdd-workflow-in-ticket-system`), does that mean Agent SDK alone can cover everything, just switching models per kind of work?

## Summary of answers

- **Scope (original):** just two providers for MVP — Anthropic API and Claude Agent SDK. Ollama, OpenAI, OpenAI-compatible, and Firebase AI Logic deferred to a later pass.
- **Cost model:** Claude Agent SDK authenticates via the user's Claude Pro/Max plan and draws from that plan's usage window — $0 marginal cost within plan limits, with Claude Code's opt-in "extra usage" billing overage at standard API rates if the window is exceeded. The Anthropic Messages API is billed separately per-token via API key, regardless of Pro/Max.
- **Scope split (original):** Claude Agent SDK covers desktop coding execution and desktop spec-phase; Messages API covers watcher reviews, ticket estimation, AI-authored comments — defaulted to Haiku 4.5/low-effort Sonnet for cost.
- **Budget gate:** pulled into this change's first pass rather than deferred, given the tight budget.
- **Watcher-driven rescoping (follow-up):** re-examining the three original reasons Messages API stayed in scope — (1) heavyweight subprocess/tool-loop overhead for a simple text-in/text-out call, (2) a background daemon competing with interactive coding sessions for the same Pro/Max rate-limit window, (3) mobile/web can't run Agent SDK at all (no subprocess access) — dropping the watcher guts (1) and (2). "AI-authored comments" was explicitly a watcher output type in `project.md` and may not exist as a use case anymore; the remaining candidates (ticket estimation, Inbox chats) are user-initiated or tied to a direct action, not a standing background process, so the overhead/rate-limit arguments mostly evaporate. Reason (3) is a hard platform constraint, not a preference, and doesn't move — but for a **desktop-only MVP**, it doesn't apply yet either. Conclusion: Agent SDK alone, switching model config per phase (model availability under Agent SDK not fully verified — flagged, not assumed), can plausibly cover coding execution, spec-phase, estimation, and Inbox chats for the desktop MVP. Anthropic Messages API (and mobile/web parity generally) becomes a clearly later idea, revisited once provider coverage improves for other agent/model types.

## Conclusions reached

- **MVP provider scope: Claude Agent SDK only.** Anthropic API, Ollama, OpenAI, OpenAI-compatible, and Firebase AI Logic are all deferred.
- Agent SDK covers everything in the desktop MVP: coding execution, spec-phase (explore/propose/verify/archive), ticket estimation, and Inbox chats — by switching model configuration per phase, not by routing to a separate provider.
- Mobile/web AI parity (which would require Messages API or the Firebase proxy, since Agent SDK can't run there) is explicitly deferred until provider coverage is revisited later — not part of this change.
- The budget-gate / automation-confidence consent system stays in scope for this change's first pass, but is reframed: it now guards against approaching the Claude Pro/Max plan's usage window (which would trigger Claude Code's opt-in overage billing) rather than a per-token Messages API cost.

## Open questions

- Exact UI flow/screen layout for Settings → Providers (now simpler with a single provider — likely just plan auto-detection + confirmation, no API key entry needed for Agent SDK).
- Whether Claude Agent SDK's model parameter actually exposes the full model range needed per phase (e.g. a lightweight tier like Haiku for ticket estimation) or defaults to a narrower coding-agent-oriented set — not verified, flagged for `/propose` or implementation time.
- When mobile/web parity is eventually revisited, whether it's a new idea from scratch or a direct continuation of this one (`related_ideas` link is in place either way).

## Architectural implications

- Refines project.md's Foundational Decision §3 (Agentic Engine) toward a much smaller desktop-only MVP: a single `AgentModelClient` implementation (Claude Agent SDK) rather than the originally-envisioned multi-provider `ModelRouter`.
- `AutomationConfidence` (three-state: `auto | gated | manual`, per `sdd-workflow-in-ticket-system`) is still built here as part of the budget gate — this change is its first real implementation, later reused by SDD-stage-triggering and the batch-flush gate.
- Simplifies `new-project-onboarding`'s Inbox feature and `sdd-workflow-in-ticket-system`'s Execution phase, both of which depend on this change for a working chat provider — neither needs to plan for a second provider anymore.
- This is now the smallest and fastest of the three explored ideas to `/propose` — a strong candidate to sequence first.