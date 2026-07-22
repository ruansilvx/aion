// presentation/cubit/automation_settings_cubit.dart — AutomationSettingsCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/core/automation/automation_confidence.dart';
import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/automation_settings_repository.dart';
import 'package:aion/features/providers/presentation/cubit/automation_settings_state.dart';

/// Business logic for the Settings screen's automation sections ("SDD
/// Stage Automation", "Coding Execution Automation"): loads the
/// persisted [AutomationConfidence] for every [AutomationContext] and
/// persists changes to any one of them. Kept separate from
/// `ProviderSettingsCubit` since the two concerns (provider connection
/// vs. automation confidence) are unrelated — one cubit per concern, per
/// `project.md`'s Cubit-vs-repository split.
class AutomationSettingsCubit extends Cubit<AutomationSettingsState> {
  /// Creates an [AutomationSettingsCubit] backed by [_repository].
  AutomationSettingsCubit(this._repository)
    : super(const AutomationSettingsLoading());

  final AutomationSettingsRepository _repository;

  /// Loads the persisted confidence level for every [AutomationContext]
  /// and emits [AutomationSettingsReady].
  Future<void> load() async {
    final results = await Future.wait(
      AutomationContext.values.map(_repository.getConfidence),
    );
    if (isClosed) return;
    emit(
      AutomationSettingsReady(
        Map.fromIterables(AutomationContext.values, results),
      ),
    );
  }

  /// Persists [confidence] as [context]'s new selection and re-emits
  /// [AutomationSettingsReady] with that entry updated.
  Future<void> selectConfidence(
    AutomationContext context,
    AutomationConfidence confidence,
  ) async {
    await _repository.setConfidence(context, confidence);
    if (isClosed) return;
    final current = state;
    final updated = current is AutomationSettingsReady
        ? Map<AutomationContext, AutomationConfidence>.of(
            current.confidenceByContext,
          )
        : <AutomationContext, AutomationConfidence>{};
    updated[context] = confidence;
    emit(AutomationSettingsReady(updated));
  }
}
