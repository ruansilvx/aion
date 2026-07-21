// core/automation/automation_settings_repository.dart — AutomationSettingsRepository interface (core layer).

import 'package:aion/core/automation/automation_confidence.dart';

/// Persists the single global [AutomationConfidence] value for
/// SDD-stage-triggering (see `TicketsCubit.advanceSddStage`). One value
/// today; per-context storage (a keyed value per automation point) is
/// deferred until a second consumer (budget gate, batch-flush gate)
/// actually exists — see `project.md` §5. Implemented by the data layer
/// ([SharedPrefsAutomationSettingsRepository]); UI and domain code depend
/// only on this interface, never on a concrete data source.
abstract interface class AutomationSettingsRepository {
  /// Returns the persisted confidence level, defaulting to
  /// [AutomationConfidence.gated] if none has been saved yet — surfaces
  /// a suggestion rather than acting silently or requiring the user to
  /// discover a manual control, the safest default for a brand-new
  /// automated decision point.
  Future<AutomationConfidence> getSddStageAutomation();

  /// Persists [confidence] as the SDD-stage-triggering confidence level.
  Future<void> setSddStageAutomation(AutomationConfidence confidence);
}
