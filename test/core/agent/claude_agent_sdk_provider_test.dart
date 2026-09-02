import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/agent/agent_bridge_locator.dart';
import 'package:aion/core/agent/claude_agent_sdk_provider.dart';
import 'package:aion/core/contracts/consumption_signal.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/tool_access_tier.dart';

void main() {
  group('ClaudeAgentSdkProvider', () {
    final provider = ClaudeAgentSdkProvider(AgentBridgeLocator());

    test('id is claudeAgentSdk', () {
      expect(provider.id, ProviderId.claudeAgentSdk);
    });

    test('availableModels lists Opus 4.8, Sonnet 5, and Haiku 4.5, all '
        'scoped to claudeAgentSdk', () {
      final models = provider.availableModels;

      expect(models, hasLength(3));
      for (final model in models) {
        expect(model.providerId, ProviderId.claudeAgentSdk);
      }
      expect(models[0].modelId, 'claude-opus-4-8');
      expect(models[0].label, 'Opus 4.8');
      expect(models[1].modelId, 'claude-sonnet-5');
      expect(models[1].label, 'Sonnet 5');
      expect(models[2].modelId, 'claude-haiku-4-5');
      expect(models[2].label, 'Haiku 4.5');
    });

    test(
      'supportedToolAccessTiers is noTools and full, not readOnly',
      () {
        expect(
          provider.supportedToolAccessTiers,
          {ToolAccessTier.noTools, ToolAccessTier.full},
        );
        expect(
          provider.supportedToolAccessTiers.contains(ToolAccessTier.readOnly),
          isFalse,
        );
      },
    );

    test('supportsSkillDiscovery is true', () {
      expect(provider.supportsSkillDiscovery, isTrue);
    });

    test('describeOverage wraps the message in UsageWindowConsumption', () {
      final signal = provider.describeOverage('usage window exhausted');

      expect(signal, isA<UsageWindowConsumption>());
      expect(signal.message, 'usage window exhausted');
    });

    test(
      'normalizeErrorMessage strips a slash-command instruction and '
      'vendor identity mentions',
      () {
        final normalized = provider.normalizeErrorMessage(
          'Authentication failed. Please run `/login` to reauthenticate '
          'Claude Code.',
        );

        expect(normalized, isNot(contains('/login')));
        expect(normalized, isNot(contains('Claude Code')));
        expect(normalized, contains('Authentication failed'));
      },
    );

    test(
      'normalizeErrorMessage passes an unrecognized message through '
      'unchanged',
      () {
        const rawMessage = 'Network timeout while contacting the API.';

        expect(provider.normalizeErrorMessage(rawMessage), rawMessage);
      },
    );
  });
}
