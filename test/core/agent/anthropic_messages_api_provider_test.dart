import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/agent/anthropic_messages_api_provider.dart';
import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/consumption_signal.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/tool_access_tier.dart';

class MockAgentModelClient extends Mock implements AgentModelClient {}

void main() {
  group('AnthropicMessagesApiProvider', () {
    final provider = AnthropicMessagesApiProvider(MockAgentModelClient());

    test('id is anthropicMessagesApi', () {
      expect(provider.id, ProviderId.anthropicMessagesApi);
    });

    test('displayName is Anthropic API', () {
      expect(provider.displayName, 'Anthropic API');
    });

    test(
      'availableModels lists three descriptors, all scoped to '
      'anthropicMessagesApi',
      () {
        final models = provider.availableModels;

        expect(models, hasLength(3));
        for (final model in models) {
          expect(model.providerId, ProviderId.anthropicMessagesApi);
        }
        expect(models[0].label, 'Opus 4.8');
        expect(models[1].label, 'Sonnet 5');
        expect(models[2].label, 'Haiku 4.5');
      },
    );

    test('supportedToolAccessTiers is noTools only', () {
      expect(provider.supportedToolAccessTiers, {ToolAccessTier.noTools});
    });

    test(
      'describeOverage wraps the message in CostConsumption with a null '
      'amountUsd',
      () {
        final signal = provider.describeOverage('rate limited');

        expect(signal, isA<CostConsumption>());
        expect(signal.message, 'rate limited');
        expect((signal as CostConsumption).amountUsd, isNull);
      },
    );

    test('normalizeErrorMessage maps a known HTTP status to a fixed '
        'vendor-neutral phrase', () {
      expect(
        provider.normalizeErrorMessage('HTTP 401 error.'),
        'Invalid API key.',
      );
      expect(
        provider.normalizeErrorMessage('HTTP 429 error.'),
        'Rate limited — too many requests.',
      );
    });

    test(
      'normalizeErrorMessage strips vendor-identity mentions for an '
      'unrecognized message',
      () {
        final normalized = provider.normalizeErrorMessage(
          'Anthropic API request failed unexpectedly.',
        );

        expect(normalized, isNot(contains('Anthropic')));
        expect(normalized, contains('request failed unexpectedly'));
      },
    );

    test(
      'normalizeErrorMessage passes a message through unchanged when '
      'nothing matches',
      () {
        const rawMessage = 'Connection reset by peer.';

        expect(provider.normalizeErrorMessage(rawMessage), rawMessage);
      },
    );
  });
}
