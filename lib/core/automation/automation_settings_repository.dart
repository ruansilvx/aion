// core/automation/automation_settings_repository.dart — AutomationSettingsRepository interface (core layer).

import 'package:aion/core/automation/automation_confidence.dart';
import 'package:aion/core/automation/automation_context.dart';

/// Persists an [AutomationConfidence] value per [AutomationContext] —
/// SDD-stage-triggering (see `TicketsCubit.advanceSddStage`) and
/// coding-execution completion (see `TicketsCubit._runCodingExecution`)
/// each get their own independently-stored value. Implemented by the
/// data layer ([SharedPrefsAutomationSettingsRepository]); UI and domain
/// code depend only on this interface, never on a concrete data source.
abstract interface class AutomationSettingsRepository {
  /// Returns the persisted confidence level for [context], defaulting to
  /// [AutomationConfidence.gated] if none has been saved yet — surfaces
  /// a suggestion rather than acting silently or requiring the user to
  /// discover a manual control, the safest default for a brand-new
  /// automated decision point.
  Future<AutomationConfidence> getConfidence(AutomationContext context);

  /// Persists [confidence] as [context]'s automation confidence level.
  Future<void> setConfidence(
    AutomationContext context,
    AutomationConfidence confidence,
  );
}
