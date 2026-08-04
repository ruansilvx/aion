// core/contracts/provider_id.dart — ProviderId enum (core layer).

/// Extensible identifier for a registered [AgentProvider]. Add a value
/// here (and a matching `AgentProvider` implementation registered in
/// `main.dart`'s `ProviderRegistry`) to add a new provider — nothing else
/// in this file changes. One value today: this MVP has exactly one
/// provider, the bundled Claude Agent SDK bridge. See
/// `aion-arch/changes/pluggable-provider-abstraction/design.md` §1.
enum ProviderId {
  /// The bundled Claude Agent SDK Node.js bridge — see
  /// `core/agent/claude_agent_sdk_provider.dart`.
  claudeAgentSdk,
}
