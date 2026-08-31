// core/agent/claude_agent_sdk_provider.dart — ClaudeAgentSdkProvider (core layer).

import 'package:aion/core/agent/agent_bridge_locator.dart';
import 'package:aion/core/agent/claude_agent_sdk_client.dart';
import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/consumption_signal.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/tool_access_tier.dart';

/// The sole [AgentProvider] implementation for this MVP — wraps the
/// existing [ClaudeAgentSdkClient] unchanged. See
/// `aion-arch/changes/pluggable-provider-abstraction/design.md` §2.
class ClaudeAgentSdkProvider implements AgentProvider {
  /// Creates a [ClaudeAgentSdkProvider], internally building a
  /// [ClaudeAgentSdkClient] from [bridgeLocator].
  ClaudeAgentSdkProvider(AgentBridgeLocator bridgeLocator)
    : client = ClaudeAgentSdkClient(bridgeLocator);

  @override
  final AgentModelClient client;

  @override
  ProviderId get id => ProviderId.claudeAgentSdk;

  @override
  String get displayName => 'Claude Agent SDK';

  /// No [ToolAccessTier.readOnly] — `agent_bridge/index.mjs` has no
  /// allowlist tier today, only `allowedTools: []` or the SDK's full
  /// default set. Honest about current capability, not aspirational.
  @override
  Set<ToolAccessTier> get supportedToolAccessTiers => const {
    ToolAccessTier.noTools,
    ToolAccessTier.full,
  };

  @override
  List<AgentModelDescriptor> get availableModels => const [
    AgentModelDescriptor(
      providerId: ProviderId.claudeAgentSdk,
      modelId: 'claude-opus-4-8',
      label: 'Opus 4.8',
      contextWindowTokens: 200000,
    ),
    AgentModelDescriptor(
      providerId: ProviderId.claudeAgentSdk,
      modelId: 'claude-sonnet-5',
      label: 'Sonnet 5',
      contextWindowTokens: 200000,
    ),
    AgentModelDescriptor(
      providerId: ProviderId.claudeAgentSdk,
      modelId: 'claude-haiku-4-5',
      label: 'Haiku 4.5',
      contextWindowTokens: 200000,
    ),
  ];

  @override
  ConsumptionSignal describeOverage(String rawMessage) =>
      UsageWindowConsumption(rawMessage);

  /// Strips CLI-instruction/vendor-identity text that leaks Claude
  /// Code's own tooling identity into Aion's provider-agnostic UI — the
  /// complaint `provider-error-messages-leak-vendor-text.md` raised.
  /// Strips any `/slash-command` fragment (e.g. "run `/login`" — a
  /// Claude Code CLI instruction meaningless inside Aion) and literal
  /// "Claude Code"/"claude-agent-sdk" mentions. Falls back to
  /// [rawMessage] unchanged if no known pattern matched, or if stripping
  /// would leave nothing behind — never hides a real error, only cleans
  /// vendor identity out of it.
  @override
  String normalizeErrorMessage(String rawMessage) {
    var message = rawMessage.replaceAll(RegExp(r'`?/[a-zA-Z][\w-]*`?'), '');
    for (final vendorMention in const ['Claude Code', 'claude-agent-sdk']) {
      message = message.replaceAll(vendorMention, '');
    }
    message = message.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return message.isEmpty ? rawMessage : message;
  }

  /// `true` per design.md §1's empirical finding that the Claude Agent
  /// SDK's `resume`/`forkSession` mechanism resumes a live session cheaply
  /// (near-free prompt-cache hit), even mid-turn.
  @override
  bool get supportsSessionResume => true;
}
