// presentation/cubit/anthropic_provider_config_state.dart — AnthropicProviderConfigState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/providers/domain/enums/provider_connection_status.dart';

/// The state emitted by `AnthropicProviderConfigCubit`.
sealed class AnthropicProviderConfigState extends Equatable {
  const AnthropicProviderConfigState();

  @override
  List<Object?> get props => [];
}

/// Initial state, before `AnthropicProviderConfigCubit.load` resolves.
class AnthropicProviderConfigLoading extends AnthropicProviderConfigState {
  /// Creates an [AnthropicProviderConfigLoading] state.
  const AnthropicProviderConfigLoading();
}

/// Loaded — carries whether an API key is currently stored plus the
/// current connection-check outcome. Reuses [ProviderConnectionStatus]'s
/// existing four states rather than inventing a parallel vocabulary for
/// this provider-scoped config panel.
class AnthropicProviderConfigReady extends AnthropicProviderConfigState {
  /// Creates an [AnthropicProviderConfigReady] state.
  const AnthropicProviderConfigReady({
    required this.hasApiKey,
    required this.status,
    this.statusMessage,
  });

  /// Whether a non-empty API key is currently stored.
  final bool hasApiKey;

  /// The outcome of the most recent connection test. `unknown` both
  /// before any test has run and immediately after a key is
  /// saved/cleared — a changed key invalidates any prior result.
  final ProviderConnectionStatus status;

  /// A human-readable message accompanying [status]. `null` except when
  /// [status] is [ProviderConnectionStatus.disconnected] (holds the
  /// failure reason) or [ProviderConnectionStatus.connected] (holds an
  /// overage/rate-limit notice, if the last test surfaced one).
  final String? statusMessage;

  @override
  List<Object?> get props => [hasApiKey, status, statusMessage];
}
