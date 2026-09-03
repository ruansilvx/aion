---
ticketId: AIO-37
type: idea
status: backlog
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-04T00:00:00.000
updatedAt: 2026-08-04T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Live model-list discovery for AgentProvider

## Key questions asked

1. Is there a concrete second provider planned soon that exposes a live
   model-list endpoint, or is this purely an interface-durability check
   with no near-term driver?
2. (Investigated directly, not asked) Does `AgentProvider.availableModels`'s
   current shape already accommodate a live/async fetch later, or would
   it force a real interface change?
3. For a provider whose live fetch fails or is slow, should the Settings
   dropdown fall back to a cached last-known list, an empty/error state,
   or a static per-provider fallback list?
4. Given the one registered provider has no live endpoint and would just
   wrap a static list in an already-resolved Future, is there value in
   building this now, or should the design be resolved but the code
   deferred until a real live-discovery provider is next in line?

## Summary of answers

1. No near-term second provider — this is purely about making sure
   `AgentProvider`'s interface won't need rework later.
2. Confirmed by reading `lib/core/contracts/agent_provider.dart`:
   `List<AgentModelDescriptor> get availableModels` is a plain sync
   getter, and `ModelRoutingCubit.load()` (per `providers.md`) treats it
   as instantly available with no loading/error state. A live endpoint
   needs a network call, which a sync getter can't represent — this is a
   real, not cosmetic, gap.
3. Cached last-known list is the primary source; fall back if the cache
   is empty (e.g. first run before any successful fetch).
4. Defer the code entirely — resolve the design now, build it only once
   an actual live-discovery provider is being added.

## Conclusions reached

Direction is clear but explicitly deferred: `AgentProvider.availableModels`
should eventually widen from a sync getter to an async-capable shape
(fetch + cache), with `ModelRoutingCubit` gaining a loading/error state
for it, and the Settings dropdown falling back to the cached last-known
list when a live fetch fails or the provider is slow — falling back to
an empty state only if no cache exists yet (first run). This is a
resolved architectural question, not a captured-but-unclear thought, but
there's no reason to write the code today: `ClaudeAgentSdkProvider` has
no live endpoint and would only ever wrap its existing static list in an
already-resolved `Future`, so there's no real consumer to validate the
change against. Building it now would be speculative scope with zero
observable benefit.

## Open questions

- Exact async shape (`Future<List<AgentModelDescriptor>>` one-shot fetch
  vs. a stream/refresh-on-demand method) — not resolved, since it's
  easier to pin down once a real live-discovery provider's actual API
  shape (e.g. Ollama's `/api/tags`) is in front of us.
- Where the cache lives (in-memory per session vs. persisted across
  restarts via `shared_preferences`, matching this feature's existing
  one-key-per-concept convention) — deferred for the same reason.

## Architectural implications

When this is eventually built, it folds into whichever change first
adds a genuinely live-discovery provider (see
`[[pluggable-provider-abstraction]]`, which designed `AgentProvider` but
validated it against only one implementation) — not a standalone change
against `ClaudeAgentSdkProvider` alone, since that provider has nothing
to discover.