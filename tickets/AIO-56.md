---
ticketId: AIO-56
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-23T00:00:00.000
updatedAt: 2026-08-03T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Provider connection errors leak raw vendor/CLI text into a model-agnostic UI

## What was observed

Dogfooding coding execution on 2026-07-23 (see
`coding-execution-reliability-and-safety.md` for the full session), the
very first Settings connection check failed with the SDK's own literal
error text displayed in the Provider card: "Invalid API key · Please run
`/login`." That instruction is meaningless to an Aion user — `/login` is a
Claude Code CLI slash command, not anything Aion exposes, and the actual
fix required setting up credentials for the bundled `agent_bridge` Node
process, not running any command inside Aion itself.

## Why this matters

`project.md`'s own stated design principle: "Aion is agent/model-agnostic
by design — no user-facing text, docs, or naming should hardcode a
specific vendor or model provider (Claude, Anthropic, GPT, Gemini, etc.)."
A raw SDK error string is the most direct possible violation of that
principle — it's not just naming a vendor, it's surfacing that vendor's
own internal tooling instructions verbatim, unfiltered, to a user who has
no way to act on them without reading through to the underlying
implementation (as this session had to).

## Open questions

- Should this be a general pattern (any `AgentErrorEvent`/connection-test
  failure gets passed through an Aion-authored translation layer before
  reaching UI text) or a narrow fix scoped just to the Settings
  connection-test card?
- What should Aion's own message actually say here, given the real fix is
  "the bundled agent process needs credentials," which is itself somewhat
  provider-specific (Claude Agent SDK auth, not a generic concept every
  future provider will share the same way)? Does this need per-provider
  error-translation logic, or is a generic "provider needs to be
  re-authenticated — see [docs]" good enough for now?
- Does this apply only to the Settings screen, or could the same raw-text
  leak happen anywhere else `AgentErrorEvent.message` reaches a widget
  directly (e.g. a failed chat turn's persisted "Execution failed: ..."
  comment, which currently also just echoes the SDK's own error text)?

## Architectural implications

- Extends `provider-configuration`'s shipped Settings screen (now
  archived) — this is a follow-up gap discovered after that idea shipped,
  not a revision to it, hence a new idea file rather than reopening an
  archived one.
- If a general error-translation layer is built, it likely belongs
  alongside `AgentModelClient`/`AgentErrorEvent` in `core/agent/` or
  `core/contracts/`, as something every current and future
  `AgentModelClient` implementation's errors pass through before reaching
  any Cubit state.