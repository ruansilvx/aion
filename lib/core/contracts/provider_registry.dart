// core/contracts/provider_registry.dart — ProviderRegistry abstract interface (core layer).

import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/provider_id.dart';

/// The provider-id-to-[AgentProvider] lookup every consumer goes through,
/// instead of holding a single [AgentModelClient] field directly. Constructed
/// once in `main.dart`. "Pluggable" for a compiled Flutter app means: adding
/// provider #2 is one new class + one enum value + one entry in the registry's
/// construction list — nothing else in `main.dart` or any consuming cubit
/// changes. See `AIO-1544` §1.
abstract interface class ProviderRegistry {
  /// Every registered provider.
  List<AgentProvider> get availableProviders;

  /// The registered [AgentProvider] for [id].
  ///
  /// Throws [StateError] if [id] has no registered provider — every
  /// [ProviderId] reachable from persisted `ModelRoutingRepository`
  /// state must be registered, so this is a real invariant violation,
  /// not a recoverable condition.
  AgentProvider providerById(ProviderId id);
}
