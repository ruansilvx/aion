// core/contracts/agent_session_handle.dart — AgentSessionHandle value type (core layer).

import 'package:equatable/equatable.dart';

import 'provider_id.dart';

/// A resumable handle to an in-flight [AgentModelClient.run] call's
/// provider-native session, threaded to [AgentRequest.onToolCall] so a
/// tool-call handler can ask a scoped side-question inside the same
/// conversation via a second, forked [AgentModelClient.run] call. `null`
/// wherever the underlying provider has no session concept
/// ([AgentProvider.supportsSessionResume] `false`) or [AgentRequest.tools] is
/// empty. See `AIO-613/ design.md` §4.
class AgentSessionHandle extends Equatable {
  /// Creates an [AgentSessionHandle] for [sessionId] on [providerId],
  /// running [modelId].
  const AgentSessionHandle({
    required this.providerId,
    required this.sessionId,
    required this.modelId,
  });

  /// Which registered [AgentProvider] this session belongs to — resolved
  /// back via `ProviderRegistry.providerById` at the call site that
  /// wants to make the round-trip call.
  final ProviderId providerId;

  /// The provider-native session identifier to resume.
  final String sessionId;

  /// The exact model id the in-flight run is using — see design.md §3
  /// for why a round trip must reuse it rather than a cheaper tier.
  final String modelId;

  @override
  List<Object?> get props => [providerId, sessionId, modelId];
}
