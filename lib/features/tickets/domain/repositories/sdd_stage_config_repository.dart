// domain/repositories/sdd_stage_config_repository.dart — SddStageConfigRepository interface (domain layer).

import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';

/// Persists a project's `SddStage` configuration: whether the design-review
/// stages (`SddStage.designBrief`/`.designSync`) are required at all, and
/// an optional per-stage display-name override. Mirrors
/// `AutomationSettingsRepository`'s exact shape — the correct-fit precedent
/// per `/explore` (not `ProjectOverride`, which only shadows bundled
/// files). Implemented by the data layer
/// ([SharedPrefsSddStageConfigRepository]); UI and domain code depend only
/// on this interface, never on a concrete data source. See
/// `aion-arch/changes/configurable-ticket-workflow/design.md` §1.5.
abstract interface class SddStageConfigRepository {
  /// Whether Epics/Stories must clear the `designBrief`/`designSync` stage
  /// cycle before execution. Defaults to `true` — matches today's
  /// automatic per-Story heuristic (`TicketsCubit._storyNeedsDesignReview`)
  /// being effectively "on" for every project that hasn't opted out.
  Future<bool> getDesignStagesEnabled();

  /// Persists [enabled] as the project's design-stages-required setting.
  Future<void> setDesignStagesEnabled(bool enabled);

  /// Returns the persisted display-name override for [stage], or `null` if
  /// none has been set — meaning "use `SddStage`'s own hardcoded display
  /// name."
  Future<String?> getDisplayNameOverride(SddStage stage);

  /// Persists [displayName] as [stage]'s display-name override. Pass
  /// `null` to clear the override and revert to the hardcoded default
  /// name.
  Future<void> setDisplayNameOverride(SddStage stage, String? displayName);
}
