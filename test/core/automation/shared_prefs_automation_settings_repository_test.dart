import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/core/automation/automation_confidence.dart';
import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/shared_prefs_automation_settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsAutomationSettingsRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'getConfidence defaults to gated for both contexts when unset',
      () async {
        final repository = SharedPrefsAutomationSettingsRepository();

        expect(
          await repository.getConfidence(AutomationContext.sddStage),
          AutomationConfidence.gated,
        );
        expect(
          await repository.getConfidence(AutomationContext.codingExecution),
          AutomationConfidence.gated,
        );
      },
    );

    test(
      'setConfidence then getConfidence round-trips independently per '
      'context',
      () async {
        final repository = SharedPrefsAutomationSettingsRepository();

        await repository.setConfidence(
          AutomationContext.sddStage,
          AutomationConfidence.auto,
        );
        await repository.setConfidence(
          AutomationContext.codingExecution,
          AutomationConfidence.manual,
        );

        expect(
          await repository.getConfidence(AutomationContext.sddStage),
          AutomationConfidence.auto,
        );
        expect(
          await repository.getConfidence(AutomationContext.codingExecution),
          AutomationConfidence.manual,
        );
      },
    );

    test(
      "AutomationContext.sddStage preserves the pre-existing "
      "'automation_settings.sdd_stage_automation' key, so an already-saved "
      'user preference survives the per-context generalization',
      () async {
        SharedPreferences.setMockInitialValues({
          'automation_settings.sdd_stage_automation': 'auto',
        });
        final repository = SharedPrefsAutomationSettingsRepository();

        expect(
          await repository.getConfidence(AutomationContext.sddStage),
          AutomationConfidence.auto,
        );
      },
    );

    test(
      'AutomationContext.codingExecution is stored under its own new key, '
      "independent of sddStage's key",
      () async {
        final repository = SharedPrefsAutomationSettingsRepository();

        await repository.setConfidence(
          AutomationContext.codingExecution,
          AutomationConfidence.auto,
        );

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('automation_settings.coding_execution_automation'),
          'auto',
        );
        expect(
          prefs.getString('automation_settings.sdd_stage_automation'),
          isNull,
        );
      },
    );
  });
}
