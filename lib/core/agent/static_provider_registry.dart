// core/agent/static_provider_registry.dart — StaticProviderRegistry (core layer).

import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/provider_registry.dart';

/// [ProviderRegistry] implementation backed by a plain, fixed
/// `List<AgentProvider>` supplied at construction — no dynamic
/// registration, no I/O. Constructed once in `main.dart` with every
/// provider Aion ships. See
/// `AIO-1544` §1.
class StaticProviderRegistry implements ProviderRegistry {
  /// Creates a [StaticProviderRegistry] backed by [availableProviders].
  const StaticProviderRegistry(this.availableProviders);

  @override
  final List<AgentProvider> availableProviders;

  @override
  AgentProvider providerById(ProviderId id) {
    for (final provider in availableProviders) {
      if (provider.id == id) return provider;
    }
    throw StateError('No AgentProvider registered for $id.');
  }
}
