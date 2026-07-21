// domain/enums/agent_model.dart — AgentModel enum (domain layer).

/// The fixed set of models this MVP lets the user pick between in
/// Settings. Not discovered from a live endpoint (unlike Ollama's planned
/// `/api/tags` fetch) — Claude Agent SDK has no equivalent endpoint.
/// Extend this enum, not a Settings-screen rewrite, if the confirmed-working
/// model set changes.
enum AgentModel {
  /// Claude Opus 4.8 — `claude-opus-4-8`. Highest capability, highest cost.
  opus('claude-opus-4-8', 'Opus 4.8'),

  /// Claude Sonnet 5 — `claude-sonnet-5`. Default balanced choice.
  sonnet('claude-sonnet-5', 'Sonnet 5'),

  /// Claude Haiku 4.5 — `claude-haiku-4-5`. Fastest, cheapest.
  haiku('claude-haiku-4-5', 'Haiku 4.5');

  const AgentModel(this.id, this.label);

  /// The identifier passed as `AgentRequest.model`
  /// (`core/contracts/agent_model_client.dart`).
  final String id;

  /// Human-readable label for the Settings model dropdown.
  final String label;
}
