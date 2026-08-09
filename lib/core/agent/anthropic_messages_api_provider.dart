// core/agent/anthropic_messages_api_provider.dart — AnthropicMessagesApiProvider (core layer).

import 'package:aion/core/agent/anthropic_messages_api_client.dart';
import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/consumption_signal.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/tool_access_tier.dart';

/// The second [AgentProvider] implementation — wraps
/// [AnthropicMessagesApiClient], a plain HTTP-backed client, rather than
/// `ClaudeAgentSdkProvider`'s bundled bridge/subprocess machinery, which
/// this provider has none of. Text-only: declares
/// [ToolAccessTier.noTools] only, so `ModelPhaseToolAccess`'s filter never
/// offers this provider's models to the Execution tier. See
/// `aion-arch/changes/anthropic-messages-api-provider/design.md` §3.
class AnthropicMessagesApiProvider implements AgentProvider {
  /// Creates an [AnthropicMessagesApiProvider] running requests through
  /// [client].
  AnthropicMessagesApiProvider(this.client);

  @override
  final AgentModelClient client;

  @override
  ProviderId get id => ProviderId.anthropicMessagesApi;

  @override
  String get displayName => 'Anthropic API';

  /// Text-only — no file edits, git, bash, or MCP. Building an agentic
  /// tool loop against the raw Messages API is out of scope for this
  /// provider (see proposal.md's Non-goals);
  /// `ClaudeAgentSdkProvider` gets that for free from the bundled Agent
  /// SDK bridge.
  @override
  Set<ToolAccessTier> get supportedToolAccessTiers => const {
    ToolAccessTier.noTools,
  };

  /// Three models mirroring `ClaudeAgentSdkProvider.availableModels`'s
  /// Opus/Sonnet/Haiku labels, using the same Anthropic model-id strings
  /// that provider already ships with — the Agent SDK's `--model` values
  /// are themselves Messages API model identifiers, so reusing them here
  /// is a real, non-invented id, not a guess.
  @override
  List<AgentModelDescriptor> get availableModels => const [
    AgentModelDescriptor(
      providerId: ProviderId.anthropicMessagesApi,
      modelId: 'claude-opus-4-8',
      label: 'Opus 4.8',
      contextWindowTokens: 200000,
    ),
    AgentModelDescriptor(
      providerId: ProviderId.anthropicMessagesApi,
      modelId: 'claude-sonnet-5',
      label: 'Sonnet 5',
      contextWindowTokens: 200000,
    ),
    AgentModelDescriptor(
      providerId: ProviderId.anthropicMessagesApi,
      modelId: 'claude-haiku-4-5',
      label: 'Haiku 4.5',
      contextWindowTokens: 200000,
    ),
  ];

  /// First real [CostConsumption] producer — a 429 (rate-limited) response
  /// from `AnthropicMessagesApiClient` is a token-billed provider's
  /// consumption signal, not `ClaudeAgentSdkProvider`'s flat-plan
  /// [UsageWindowConsumption]. `amountUsd` stays `null`: the API's 429
  /// body doesn't carry a dollar figure.
  @override
  ConsumptionSignal describeOverage(String rawMessage) =>
      CostConsumption(rawMessage, null);

  /// Strips vendor-identity text that would otherwise leak Anthropic's own
  /// API error phrasing into Aion's provider-agnostic UI — same spirit as
  /// `ClaudeAgentSdkProvider.normalizeErrorMessage`'s CLI-instruction
  /// stripping, applied to this provider's own vendor surface instead.
  /// Maps common HTTP status-code phrasing to a vendor-neutral message;
  /// falls back to [rawMessage] unchanged if nothing matches, or if
  /// stripping would leave nothing behind — never hides a real error, only
  /// cleans vendor identity out of it.
  @override
  String normalizeErrorMessage(String rawMessage) {
    final knownStatusMessage = switch (rawMessage) {
      _ when rawMessage.contains('HTTP 401') => 'Invalid API key.',
      _ when rawMessage.contains('HTTP 403') =>
        'This API key does not have permission for this request.',
      _ when rawMessage.contains('HTTP 404') => 'Model not found.',
      _ when rawMessage.contains('HTTP 429') =>
        'Rate limited — too many requests.',
      _ when rawMessage.contains('HTTP 5') => 'Anthropic API is unavailable.',
      _ => null,
    };
    if (knownStatusMessage != null) return knownStatusMessage;

    var message = rawMessage;
    for (final vendorMention in const ['Anthropic', 'anthropic-messages-api']) {
      message = message.replaceAll(vendorMention, '');
    }
    message = message.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return message.isEmpty ? rawMessage : message;
  }
}
