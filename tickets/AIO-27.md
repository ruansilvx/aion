---
ticketId: AIO-27
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
# delegatedSkill attachments have no real provider-portability guarantee

## Key questions asked

Surfaced as a tangent while brainstorming
[[decommission-aion-arch-cli-workflow]] — no independent question
sequence of its own; see that idea's session log for the questions
that led here. This file exists because the finding is a genuinely
separate, pre-existing issue rather than part of that decommission.

## Summary of answers

- `SkillAttachmentKind.delegatedSkill`
  (`aion/lib/features/tickets/domain/enums/skill_attachment_kind.dart`)
  sends the literal prompt `/<skillName>`, tool-enabled, relying on
  the underlying coding agent to discover `.claude/skills/<skillName>`
  on disk — the exact same file-based, Claude-Code-native convention
  `aion-arch` itself uses today, not something Aion's own code
  interprets or injects.
- The sibling kind, `aionNativeTemplate`, is genuinely provider-
  agnostic — plain-text prompt substitution via
  `renderWorkflowPromptTemplate`, no CLI-specific behavior.
- `AnthropicMessagesApiProvider` (`aion/lib/core/agent/
  anthropic_messages_api_provider.dart`) is a real, already-shipped
  second `AgentProvider` declaring `supportedToolAccessTiers:
  {noTools}` only. `ModelRoutingCubit` filters providers by
  `supportedToolAccessTiers` against each `ModelPhase`'s required
  tier, so this provider is already correctly never offered for
  `delegatedSkill` (which needs `ModelPhase.execution`/full tool
  access). Today's actual second provider can't hit this gap.
- The filter only checks "can this provider call tools at all," not
  "can this provider discover `.claude/skills/*` files." A
  hypothetical future full-tool-access provider that isn't a
  Claude-Code-CLI wrapper would pass `ModelPhaseToolAccess`'s filter
  and still be offered for `delegatedSkill`, then fail (or silently
  no-op) at runtime — nothing in the `AgentProvider` contract actually
  requires or checks for `.claude/skills/` discovery capability
  specifically.
- This is independent of `aion-arch`'s fate — it would matter the
  moment any non-Claude-Code-CLI full-tool provider ships, regardless
  of whether the decommission happens. Explicitly not folded into
  [[decommission-aion-arch-cli-workflow]]'s scope for that reason, but
  flagged as needing a fix *before* that migration proceeds, since the
  migration's own execution likely leans on `delegatedSkill`-style
  mechanisms.

## Conclusions reached

Confirmed as a real, pre-existing gap: `delegatedSkill` attachments
only work when the resolved provider is literally a Claude-Code-CLI
wrapper capable of file-based `.claude/skills/` discovery, and nothing
in the `AgentProvider`/`ToolAccessTier` contract captures that
requirement beyond "supports full tool access." Scoped as its own
issue, separate from decommissioning `aion-arch`, and prioritized to
be fixed before that migration proceeds.

## Open questions

- What the actual fix looks like — candidates not yet evaluated:
  a new `AgentProvider` capability flag (e.g.
  `supportsSkillDiscovery`) that `ModelPhaseToolAccess`/
  `ModelRoutingCubit` filters on in addition to `ToolAccessTier`; or
  restricting `delegatedSkill` attachments to providers explicitly
  known to be CLI-bridge-based; or Aion's own code taking over skill
  *content* injection itself (reading `.claude/skills/<name>/SKILL.md`
  and rendering it into the prompt directly, sidestepping reliance on
  the underlying agent's own discovery entirely — closer to how
  `aionNativeTemplate` already works).
- Whether a fix needs a new capability signal on `AgentProvider` at
  all, or whether `delegatedSkill` should simply be documented/
  enforced as "requires `ClaudeAgentSdkProvider` specifically" until a
  second CLI-bridge-style provider actually exists.

**Resolved by `/propose` (2026-09-01):** a new `AgentProvider
.supportsSkillDiscovery` capability bool, checked only at
`TicketsCubit._fireSkillAttachment`'s provider-resolution call site —
not a `ModelPhaseToolAccess`/dropdown-level filter (that filter is
phase-wide and shared with plain coding-execution runs, which have no
skill-discovery dependency), and not a hardcoded `is
ClaudeAgentSdkProvider` check (would violate the pluggable-provider
architecture's "adding provider #2 is one new class" invariant). Mirrors
the existing `supportsSessionResume` precedent exactly. The
"Aion reads `.claude/skills/*.md` itself" option is deferred as a
follow-up idea, not built now — see
`aion-arch/changes/delegated-skill-provider-portability/proposal.md`'s
Non-goals.

## Architectural implications

- Blocks/gates [[decommission-aion-arch-cli-workflow]]'s migration —
  that idea's plan assumes providers can reliably run skill-driven
  work; this gap should close first.
- Touches `AgentProvider`/`ToolAccessTier`/`ModelPhaseToolAccess`
  (`aion/lib/core/contracts/`, `aion/lib/features/providers/`) and
  `SkillAttachmentKind`/`WorkflowConfigCubit`
  (`aion/lib/features/tickets/`).
- Relevant to [[pluggable-provider-abstraction]] — any future provider
  added under that mechanism inherits this gap until it's fixed.