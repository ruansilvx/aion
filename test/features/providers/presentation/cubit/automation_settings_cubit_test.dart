import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/automation/automation_confidence.dart';
import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/automation_settings_repository.dart';
import 'package:aion/features/providers/providers.dart';

class MockAutomationSettingsRepository extends Mock
    implements AutomationSettingsRepository {}

void main() {
  late MockAutomationSettingsRepository repository;

  setUpAll(() {
    registerFallbackValue(AutomationConfidence.gated);
  });

  setUp(() {
    repository = MockAutomationSettingsRepository();
  });

  group('AutomationSettingsCubit', () {
    blocTest<AutomationSettingsCubit, AutomationSettingsState>(
      'load fetches both AutomationContext values and emits a keyed map',
      setUp: () {
        when(
          () => repository.getConfidence(AutomationContext.sddStage),
        ).thenAnswer((_) async => AutomationConfidence.auto);
        when(
          () => repository.getConfidence(AutomationContext.codingExecution),
        ).thenAnswer((_) async => AutomationConfidence.manual);
      },
      build: () => AutomationSettingsCubit(repository),
      act: (cubit) => cubit.load(),
      expect: () => [
        const AutomationSettingsReady({
          AutomationContext.sddStage: AutomationConfidence.auto,
          AutomationContext.codingExecution: AutomationConfidence.manual,
        }),
      ],
    );

    blocTest<AutomationSettingsCubit, AutomationSettingsState>(
      'selectConfidence persists the chosen context only, leaving the '
      "other context's entry in the re-emitted map untouched",
      setUp: () {
        when(
          () => repository.setConfidence(
            AutomationContext.codingExecution,
            AutomationConfidence.gated,
          ),
        ).thenAnswer((_) async {});
      },
      build: () => AutomationSettingsCubit(repository),
      seed: () => const AutomationSettingsReady({
        AutomationContext.sddStage: AutomationConfidence.auto,
        AutomationContext.codingExecution: AutomationConfidence.manual,
      }),
      act: (cubit) => cubit.selectConfidence(
        AutomationContext.codingExecution,
        AutomationConfidence.gated,
      ),
      expect: () => [
        const AutomationSettingsReady({
          AutomationContext.sddStage: AutomationConfidence.auto,
          AutomationContext.codingExecution: AutomationConfidence.gated,
        }),
      ],
      verify: (_) {
        verifyNever(
          () => repository.setConfidence(
            AutomationContext.sddStage,
            any(),
          ),
        );
      },
    );
  });
}
