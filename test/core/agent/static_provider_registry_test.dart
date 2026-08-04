import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/agent/agent_bridge_locator.dart';
import 'package:aion/core/agent/claude_agent_sdk_provider.dart';
import 'package:aion/core/agent/static_provider_registry.dart';
import 'package:aion/core/contracts/provider_id.dart';

void main() {
  group('StaticProviderRegistry', () {
    test('availableProviders returns exactly the constructed list', () {
      final provider = ClaudeAgentSdkProvider(AgentBridgeLocator());
      final registry = StaticProviderRegistry([provider]);

      expect(registry.availableProviders, [provider]);
    });

    test('providerById returns the matching registered provider', () {
      final provider = ClaudeAgentSdkProvider(AgentBridgeLocator());
      final registry = StaticProviderRegistry([provider]);

      expect(
        registry.providerById(ProviderId.claudeAgentSdk),
        same(provider),
      );
    });

    test('providerById throws StateError when no provider is registered '
        'for the given id', () {
      final registry = StaticProviderRegistry(const []);

      expect(
        () => registry.providerById(ProviderId.claudeAgentSdk),
        throwsStateError,
      );
    });
  });
}
