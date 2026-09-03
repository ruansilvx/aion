// core/contracts/provider_id.dart — ProviderId enum (core layer).

/// Extensible identifier for a registered [AgentProvider]. Add a value
/// here (and a matching `AgentProvider` implementation registered in
/// `main.dart`'s `ProviderRegistry`) to add a new provider — nothing else
/// in this file changes. Two values today: the bundled Claude Agent SDK
/// bridge, and the Anthropic Messages API called directly over HTTP. See
/// `AIO-1544` §1 and
/// `AIO-110` §1.
enum ProviderId {
  /// The bundled Claude Agent SDK Node.js bridge — see
  /// `core/agent/claude_agent_sdk_provider.dart`.
  claudeAgentSdk,

  /// The Anthropic Messages API, called directly over HTTP/SSE — see
  /// `core/agent/anthropic_messages_api_provider.dart`.
  anthropicMessagesApi,
}
