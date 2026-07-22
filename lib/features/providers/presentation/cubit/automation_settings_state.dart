// presentation/cubit/automation_settings_state.dart — AutomationSettingsState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/core/automation/automation_confidence.dart';
import 'package:aion/core/automation/automation_context.dart';

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

/// Loaded — carries the persisted confidence level for every
/// [AutomationContext], keyed rather than split into named fields so a
/// future context slots in with no state-shape change.
class AutomationSettingsReady extends AutomationSettingsState {
  /// Creates an [AutomationSettingsReady] state carrying
  /// [confidenceByContext].
  const AutomationSettingsReady(this.confidenceByContext);

  /// The currently selected [AutomationConfidence] for each
  /// [AutomationContext].
  final Map<AutomationContext, AutomationConfidence> confidenceByContext;

  @override
  List<Object?> get props => [confidenceByContext];
}
