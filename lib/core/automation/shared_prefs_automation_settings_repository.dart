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
  /// `AIO-506`.
  static const _codingExecutionRetryAutomationKey =
      'automation_settings.coding_execution_retry_automation';

  /// [AutomationContext.chatBranching]'s key. Added for
  /// `AIO-1118`.
  static const _chatBranchingAutomationKey =
      'automation_settings.chat_branching_automation';

  /// [AutomationContext.codingExecutionResume]'s key. Added for
  /// `AIO-1400`.
  static const _codingExecutionResumeAutomationKey =
      'automation_settings.coding_execution_resume_automation';

  /// [AutomationContext.ticketCreation]'s key. Added for
  /// `AIO-2108`.
  static const _ticketCreationAutomationKey =
      'automation_settings.ticket_creation_automation';

  /// [AutomationContext.ticketLinking]'s key. Added for
  /// `AIO-2108`.
  static const _ticketLinkingAutomationKey =
      'automation_settings.ticket_linking_automation';

  /// [AutomationContext.specAutoLink]'s key. Added for
  /// `AIO-1998`.
  static const _specAutoLinkAutomationKey =
      'automation_settings.spec_auto_link_automation';

  /// [AutomationContext.verifyGateRetry]'s key. Added for
  /// `AIO-1905`.
  static const _verifyGateRetryAutomationKey =
      'automation_settings.verify_gate_retry_automation';

  String _keyFor(AutomationContext context) => switch (context) {
    AutomationContext.sddStage => _sddStageAutomationKey,
    AutomationContext.codingExecution => _codingExecutionAutomationKey,
    AutomationContext.codingExecutionRetry =>
      _codingExecutionRetryAutomationKey,
    AutomationContext.chatBranching => _chatBranchingAutomationKey,
    AutomationContext.codingExecutionResume =>
      _codingExecutionResumeAutomationKey,
    AutomationContext.ticketCreation => _ticketCreationAutomationKey,
    AutomationContext.ticketLinking => _ticketLinkingAutomationKey,
    AutomationContext.specAutoLink => _specAutoLinkAutomationKey,
    AutomationContext.verifyGateRetry => _verifyGateRetryAutomationKey,
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
