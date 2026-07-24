// core/automation/shared_prefs_automation_settings_repository.dart — SharedPrefsAutomationSettingsRepository (core layer).

import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/core/automation/automation_confidence.dart';
import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/automation_settings_repository.dart';

/// `shared_preferences`-backed implementation of
/// [AutomationSettingsRepository]. Stores [AutomationConfidence.name]
/// under a per-[AutomationContext] string key, mirroring
/// `SharedPrefsModelRoutingRepository`'s per-key shape.
class SharedPrefsAutomationSettingsRepository
    implements AutomationSettingsRepository {
  /// [AutomationContext.sddStage]'s key — unchanged from before
  /// per-context storage existed, so an already-saved user preference
  /// survives.
  static const _sddStageAutomationKey =
      'automation_settings.sdd_stage_automation';

  /// [AutomationContext.codingExecution]'s key.
  static const _codingExecutionAutomationKey =
      'automation_settings.coding_execution_automation';

  /// [AutomationContext.codingExecutionRetry]'s key. Added for
  /// `aion-arch/changes/coding-execution-reliability-and-safety`.
  static const _codingExecutionRetryAutomationKey =
      'automation_settings.coding_execution_retry_automation';

  String _keyFor(AutomationContext context) => switch (context) {
    AutomationContext.sddStage => _sddStageAutomationKey,
    AutomationContext.codingExecution => _codingExecutionAutomationKey,
    AutomationContext.codingExecutionRetry =>
      _codingExecutionRetryAutomationKey,
  };

  @override
  Future<AutomationConfidence> getConfidence(
    AutomationContext context,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final storedName = prefs.getString(_keyFor(context));
    return AutomationConfidence.values.firstWhere(
      (confidence) => confidence.name == storedName,
      orElse: () => AutomationConfidence.gated,
    );
  }

  @override
  Future<void> setConfidence(
    AutomationContext context,
    AutomationConfidence confidence,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(context), confidence.name);
  }
}
