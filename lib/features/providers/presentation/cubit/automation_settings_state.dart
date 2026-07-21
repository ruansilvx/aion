// presentation/cubit/automation_settings_state.dart — AutomationSettingsState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/core/automation/automation_confidence.dart';

/// The state emitted by [AutomationSettingsCubit](automation_settings_cubit.dart).
sealed class AutomationSettingsState extends Equatable {
  const AutomationSettingsState();

  @override
  List<Object?> get props => [];
}

/// Initial state, before [AutomationSettingsCubit.load] resolves.
class AutomationSettingsLoading extends AutomationSettingsState {
  /// Creates an [AutomationSettingsLoading] state.
  const AutomationSettingsLoading();
}

/// Loaded — carries the persisted SDD-stage-triggering confidence level.
class AutomationSettingsReady extends AutomationSettingsState {
  /// Creates an [AutomationSettingsReady] state carrying [confidence].
  const AutomationSettingsReady(this.confidence);

  /// The currently selected [AutomationConfidence] for SDD-stage-triggering.
  final AutomationConfidence confidence;

  @override
  List<Object?> get props => [confidence];
}
