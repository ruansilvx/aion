// presentation/cubit/automation_settings_cubit.dart — AutomationSettingsCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/core/automation/automation_confidence.dart';
import 'package:aion/core/automation/automation_settings_repository.dart';
import 'package:aion/features/providers/presentation/cubit/automation_settings_state.dart';

/// Business logic for the Settings screen's "SDD Stage Automation"
/// section: loads the persisted [AutomationConfidence] and persists
/// changes to it. Kept separate from `ProviderSettingsCubit` since the
/// two concerns (provider connection vs. automation confidence) are
/// unrelated — one cubit per concern, per `project.md`'s
/// Cubit-vs-repository split.
class AutomationSettingsCubit extends Cubit<AutomationSettingsState> {
  /// Creates an [AutomationSettingsCubit] backed by [_repository].
  AutomationSettingsCubit(this._repository)
    : super(const AutomationSettingsLoading());

  final AutomationSettingsRepository _repository;

  /// Loads the persisted confidence level and emits
  /// [AutomationSettingsReady].
  Future<void> load() async {
    final confidence = await _repository.getSddStageAutomation();
    if (isClosed) return;
    emit(AutomationSettingsReady(confidence));
  }

  /// Persists [confidence] as the new selection and re-emits
  /// [AutomationSettingsReady].
  Future<void> selectConfidence(AutomationConfidence confidence) async {
    await _repository.setSddStageAutomation(confidence);
    if (isClosed) return;
    emit(AutomationSettingsReady(confidence));
  }
}
