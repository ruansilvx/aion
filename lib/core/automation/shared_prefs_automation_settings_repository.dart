// core/automation/shared_prefs_automation_settings_repository.dart — SharedPrefsAutomationSettingsRepository (core layer).

import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/core/automation/automation_confidence.dart';
import 'package:aion/core/automation/automation_settings_repository.dart';

/// `shared_preferences`-backed implementation of
/// [AutomationSettingsRepository]. Stores [AutomationConfidence.name]
/// under a single string key, mirroring
/// `SharedPrefsAgentSettingsRepository`'s shape.
class SharedPrefsAutomationSettingsRepository
    implements AutomationSettingsRepository {
  static const _sddStageAutomationKey =
      'automation_settings.sdd_stage_automation';

  @override
  Future<AutomationConfidence> getSddStageAutomation() async {
    final prefs = await SharedPreferences.getInstance();
    final storedName = prefs.getString(_sddStageAutomationKey);
    return AutomationConfidence.values.firstWhere(
      (confidence) => confidence.name == storedName,
      orElse: () => AutomationConfidence.gated,
    );
  }

  @override
  Future<void> setSddStageAutomation(AutomationConfidence confidence) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sddStageAutomationKey, confidence.name);
  }
}
