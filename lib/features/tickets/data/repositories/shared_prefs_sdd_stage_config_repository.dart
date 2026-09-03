// data/repositories/shared_prefs_sdd_stage_config_repository.dart — SharedPrefsSddStageConfigRepository (data layer).

import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/repositories/sdd_stage_config_repository.dart';

/// `shared_preferences`-backed implementation of [SddStageConfigRepository],
/// mirroring `SharedPrefsAutomationSettingsRepository`'s exact key-naming/
/// serialization pattern: one key for the `designStagesEnabled` bool, and one
/// key per [SddStage] value for its display-name override. See `AIO-549` §2.5.
class SharedPrefsSddStageConfigRepository implements SddStageConfigRepository {
  /// Key for the design-stages-required bool.
  static const _designStagesEnabledKey =
      'sdd_stage_config.design_stages_enabled';

  /// Per-[SddStage] display-name override key prefix.
  static const _displayNameOverrideKeyPrefix =
      'sdd_stage_config.display_name_override.';

  String _displayNameOverrideKey(SddStage stage) =>
      '$_displayNameOverrideKeyPrefix${stage.name}';

  @override
  Future<bool> getDesignStagesEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_designStagesEnabledKey) ?? true;
  }

  @override
  Future<void> setDesignStagesEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_designStagesEnabledKey, enabled);
  }

  @override
  Future<String?> getDisplayNameOverride(SddStage stage) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_displayNameOverrideKey(stage));
  }

  @override
  Future<void> setDisplayNameOverride(
    SddStage stage,
    String? displayName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (displayName == null) {
      await prefs.remove(_displayNameOverrideKey(stage));
    } else {
      await prefs.setString(_displayNameOverrideKey(stage), displayName);
    }
  }
}
