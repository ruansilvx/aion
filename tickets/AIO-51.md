---
ticketId: AIO-51
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-03T00:00:00.000
updatedAt: 2026-08-03T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Pluggable provider abstraction for multi-provider model routing

## Key questions asked

1. Add a second real provider now, or just generalize the tier-routing shape while staying single-provider under the hood?
2. Define a full `AgentProvider` interface/contract now (model list, tier mapping, tool-access tiers, connection test, error normalization) with no second implementation yet, or build a second provider alongside it to prove the abstraction?
3. Of `providers.md`'s known gaps (budget/usage-window consent gate, per-ticket/per-chat manual override, live model-list discovery, auto-installed bridge deps, Node.js discovery) — which should this abstraction's interface anticipate now vs. defer to separate ideas?
4. Should budget-gating generalize as one "consumption" dimension different providers map their own semantics onto, or stay two structurally distinct gate types (usage-window vs. cost-budget) a provider declares support for?
5. Should a provider declare which tool-access tiers (no-tools/read-only/full) it's capable of, since not every provider can run tools the way Claude Agent SDK's subprocess/MCP machinery does?
6. "Combine providers" — does that mean different tiers can each be bound to a different provider, with cross-provider per-ticket/per-chat override, or just painless migration between providers one at a time?
7. Does this brainstorm also need to settle the config/registry shape (a `ProviderRegistry` + per-provider credentials/connection-test/enabled-state), since per-tier provider assignment breaks today's single hardcoded Settings block?

## Summary of answers

1. Generalize now. The user is on Claude Agent SDK today but expects to change providers, or combine providers, later — future integrations should be as painless as possible, almost plug-and-play.
2. Define the abstraction now; no second provider built as part of this idea.
3. Fold in both the budget/usage-window consent gate and the per-ticket/per-chat manual override now, since both are policy layered on top of any provider and the shape should be right from day one. Bridge-dependency auto-install and Node.js discovery stay out — they're Claude-Agent-SDK-specific subprocess plumbing a Messages-API-style provider wouldn't even need. Live model-list discovery stays a separate, already-tracked gap (the interface's model-listing method exists per Q2's scope, but live discovery behavior isn't specified here).
4. One generic consumption dimension. Providers map their own semantics onto it — usage-window fraction for a flat-rate plan like Claude Agent SDK's Pro/Max, dollars spent for a token-billed API.
5. Yes — a provider declares which tool-access tiers it supports, so Aion can refuse or gray out routing a `full`-tier Task to a provider that can't do it (e.g. a raw Messages API call with no tool-calling harness built around it).
6. Different tiers can each be assigned to a different provider (e.g. Frontier → one provider, Execution → another), and the per-ticket/per-chat override is cross-provider — pick any configured provider+model pair, not just swap within the currently-bound provider.
7. Yes, settle it: a `ProviderRegistry` mapping provider IDs to `AgentProvider` implementations, plus per-provider config storage (credentials, connection-test, enabled/disabled state), replacing today's single hardcoded Claude-Agent-SDK-only Settings block. Still populated with just one entry (Claude Agent SDK) for now.

## Conclusions reached

Define an `AgentProvider` abstraction now, with Claude Agent SDK as its first and only implementation — no second provider gets built in this change. The interface/contract covers:

- **Model listing + tier mapping** — Frontier/Capable/Execution, per `per-phase-tier-based-model-routing.md`'s existing shape, now provider-scoped instead of assuming a single global provider.
- **Tool-access tier capability declaration** — a provider states which of no-tools/read-only/full it supports; Aion uses this to gate routing.
- **Connection test + error normalization** — a provider maps its own vendor/CLI-flavored errors to a model-agnostic shape, resolving `provider-error-messages-leak-vendor-text.md` as a side effect rather than a separate change.
- **One generic consumption dimension** — usage-window vs. dollar-cost budget gating collapse into a single abstract "consumption" concept; each provider maps its own semantics onto it (Claude Agent SDK: Pro/Max usage-window fraction; a token-billed API: dollars spent).
- **Per-tier provider assignment** — each of the three tiers can independently bind to a different provider, enabling "combine providers" (e.g. Frontier on one provider, Execution on a cheaper one) rather than one global active provider.
- **Cross-provider per-ticket/per-chat manual override** — pick any configured provider+model pair, not constrained to the tier's default provider.
- **`ProviderRegistry` + per-provider config storage** — credentials, connection-test, enabled/disabled state, keyed by provider ID; replaces today's single hardcoded Claude-Agent-SDK-only Settings block. Populated with one entry (Claude Agent SDK) at ship time.

## Open questions

- Live model-list discovery (both for `AgentModel`'s three hardcoded values and for the tier dropdowns) stays deferred — the interface should expose a model-listing method, but implementing live discovery behavior is separate follow-up work, already tracked as its own known gap in `providers.md`.
- Auto-installed bridge dependencies and Node.js discovery beyond `PATH` stay Claude-Agent-SDK-specific and out of scope for this abstraction.
- Exact shape of the "consumption" unit (a normalized 0–1 fraction? a provider-defined enum of gate states?) isn't settled — left for `/propose` to work out against real code.
- Whether/how a Task's required tool-access tier is determined (today implicit) and cross-checked against a tier's bound provider's declared capabilities at routing time isn't detailed here — implementation detail for `/propose`.

## Architectural implications

- Generalizes two already-shipped, single-provider-scoped ideas — `per-phase-tier-based-model-routing.md` and `provider-configuration.md` — both of which deliberately deferred multi-provider work "to a later idea once provider coverage improves." This is that later idea.
- Resolves `provider-error-messages-leak-vendor-text.md` (still `raw`) as a natural side effect of the error-normalization piece of the interface — that idea likely doesn't need its own separate `/propose` once this ships.
- Directly targets the `providers.md` known gap "Per-phase model routing covers only one provider's models," and partially folds in two more ("No predictive budget/usage-window consent gate," "No per-ticket/per-chat manual override") by design rather than leaving them as separate follow-on gaps.
- Settings UI changes shape non-trivially: three tier dropdowns become a two-level provider+model selection per tier, plus a new per-provider config/connection-test surface (today only Claude Agent SDK has one, hardcoded).
- No second provider is built here, so the abstraction is unvalidated against a real second implementation — worth flagging as risk during `/propose`'s design phase, since interfaces designed against a single implementation sometimes need revision once a second one arrives.