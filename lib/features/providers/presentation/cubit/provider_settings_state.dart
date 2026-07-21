// presentation/cubit/provider_settings_state.dart — ProviderSettingsState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/providers/domain/enums/agent_model.dart';
import 'package:aion/features/providers/domain/enums/provider_connection_status.dart';

/// The state emitted by `ProviderSettingsCubit`.
sealed class ProviderSettingsState extends Equatable {
  const ProviderSettingsState();

  @override
  List<Object?> get props => [];
}

/// Initial state, before `ProviderSettingsCubit.load` resolves.
class ProviderSettingsLoading extends ProviderSettingsState {
  /// Creates a [ProviderSettingsLoading] state.
  const ProviderSettingsLoading();
}

/// Loaded — carries the persisted model selection plus the current
/// connection-check outcome.
class ProviderSettingsReady extends ProviderSettingsState {
  /// Creates a [ProviderSettingsReady] state.
  const ProviderSettingsReady({
    required this.selectedModel,
    required this.status,
    this.statusMessage,
  });

  /// The currently selected [AgentModel].
  final AgentModel selectedModel;

  /// The outcome of the most recent connection test.
  final ProviderConnectionStatus status;

  /// A human-readable message accompanying [status]. `null` except when
  /// [status] is [ProviderConnectionStatus.disconnected] (holds the
  /// failure reason) or [ProviderConnectionStatus.connected] (holds an
  /// overage/rate-limit notice, if the last test surfaced one — see
  /// `AgentOverageDetectedEvent`).
  final String? statusMessage;

  @override
  List<Object?> get props => [selectedModel, status, statusMessage];
}
