// test/features/providers/presentation/screens/settings_screen_test.dart —
// SettingsScreen's per-ModelPhase model rows (AIO-3000, epic AIO-2999).
//
// Every other Settings section's cubit is held in its Loading state, so only
// the provider card and the MODELS rows render — this file is scoped to the
// model-phase rows, not a full Settings screen harness.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/projects/presentation/cubit/baseline_upgrade_cubit.dart';
import 'package:aion/features/projects/presentation/cubit/baseline_upgrade_state.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/enums/provider_connection_status.dart';
import 'package:aion/features/providers/presentation/cubit/anthropic_provider_config_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/anthropic_provider_config_state.dart';
import 'package:aion/features/providers/presentation/cubit/automation_settings_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/automation_settings_state.dart';
import 'package:aion/features/providers/presentation/cubit/execution_context_cap_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/execution_context_cap_state.dart';
import 'package:aion/features/providers/presentation/cubit/execution_scheduling_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/execution_scheduling_state.dart';
import 'package:aion/features/providers/presentation/cubit/model_routing_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/model_routing_state.dart';
import 'package:aion/features/providers/presentation/cubit/provider_settings_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/provider_settings_state.dart';
import 'package:aion/features/providers/presentation/screens/settings_screen.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockProviderSettingsCubit extends MockCubit<ProviderSettingsState>
    implements ProviderSettingsCubit {}

class MockModelRoutingCubit extends MockCubit<ModelRoutingState>
    implements ModelRoutingCubit {}

class MockAutomationSettingsCubit extends MockCubit<AutomationSettingsState>
    implements AutomationSettingsCubit {}

class MockExecutionContextCapCubit extends MockCubit<ExecutionContextCapState>
    implements ExecutionContextCapCubit {}

class MockExecutionSchedulingCubit extends MockCubit<ExecutionSchedulingState>
    implements ExecutionSchedulingCubit {}

class MockAnthropicProviderConfigCubit
    extends MockCubit<AnthropicProviderConfigState>
    implements AnthropicProviderConfigCubit {}

class MockBaselineUpgradeCubit extends MockCubit<BaselineUpgradeState>
    implements BaselineUpgradeCubit {}

const _executionModel = AgentModelDescriptor(
  providerId: ProviderId.claudeAgentSdk,
  modelId: 'model-cheap',
  label: 'Cheap Executor',
  contextWindowTokens: 200000,
);
const _reviewModel = AgentModelDescriptor(
  providerId: ProviderId.claudeAgentSdk,
  modelId: 'model-strong',
  label: 'Strong Reviewer',
  contextWindowTokens: 200000,
);

void main() {
  late MockProviderSettingsCubit providerSettingsCubit;
  late MockModelRoutingCubit modelRoutingCubit;
  late MockAutomationSettingsCubit automationSettingsCubit;
  late MockExecutionContextCapCubit executionContextCapCubit;
  late MockExecutionSchedulingCubit executionSchedulingCubit;
  late MockAnthropicProviderConfigCubit anthropicProviderConfigCubit;
  late MockBaselineUpgradeCubit baselineUpgradeCubit;

  setUp(() {
    providerSettingsCubit = MockProviderSettingsCubit();
    modelRoutingCubit = MockModelRoutingCubit();
    automationSettingsCubit = MockAutomationSettingsCubit();
    executionContextCapCubit = MockExecutionContextCapCubit();
    executionSchedulingCubit = MockExecutionSchedulingCubit();
    anthropicProviderConfigCubit = MockAnthropicProviderConfigCubit();
    baselineUpgradeCubit = MockBaselineUpgradeCubit();

    whenListen(
      providerSettingsCubit,
      const Stream<ProviderSettingsState>.empty(),
      initialState: const ProviderSettingsReady(
        selectedModel: _executionModel,
        status: ProviderConnectionStatus.connected,
        providerDisplayName: 'Test Provider',
      ),
    );
    whenListen(
      modelRoutingCubit,
      const Stream<ModelRoutingState>.empty(),
      initialState: const ModelRoutingReady(
        {
          ModelPhase.frontier: _executionModel,
          ModelPhase.capable: _executionModel,
          ModelPhase.execution: _executionModel,
          ModelPhase.taskVerify: _reviewModel,
        },
        {
          ModelPhase.frontier: [_executionModel, _reviewModel],
          ModelPhase.capable: [_executionModel, _reviewModel],
          ModelPhase.execution: [_executionModel, _reviewModel],
          ModelPhase.taskVerify: [_executionModel, _reviewModel],
        },
      ),
    );
    whenListen(
      automationSettingsCubit,
      const Stream<AutomationSettingsState>.empty(),
      initialState: const AutomationSettingsLoading(),
    );
    whenListen(
      executionContextCapCubit,
      const Stream<ExecutionContextCapState>.empty(),
      initialState: const ExecutionContextCapLoading(),
    );
    whenListen(
      executionSchedulingCubit,
      const Stream<ExecutionSchedulingState>.empty(),
      initialState: const ExecutionSchedulingLoading(),
    );
    whenListen(
      anthropicProviderConfigCubit,
      const Stream<AnthropicProviderConfigState>.empty(),
      initialState: const AnthropicProviderConfigLoading(),
    );
    whenListen(
      baselineUpgradeCubit,
      const Stream<BaselineUpgradeState>.empty(),
      initialState: const BaselineUpgradeLoading(),
    );
  });

  Widget wrap() {
    return ThemeScope(
      theme: aionThemeArctic,
      child: WidgetsApp(
        color: aionThemeArctic.colors.primary,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, _) => MultiBlocProvider(
          providers: [
            BlocProvider<ProviderSettingsCubit>.value(
              value: providerSettingsCubit,
            ),
            BlocProvider<ModelRoutingCubit>.value(value: modelRoutingCubit),
            BlocProvider<AutomationSettingsCubit>.value(
              value: automationSettingsCubit,
            ),
            BlocProvider<ExecutionContextCapCubit>.value(
              value: executionContextCapCubit,
            ),
            BlocProvider<ExecutionSchedulingCubit>.value(
              value: executionSchedulingCubit,
            ),
            BlocProvider<AnthropicProviderConfigCubit>.value(
              value: anthropicProviderConfigCubit,
            ),
            BlocProvider<BaselineUpgradeCubit>.value(
              value: baselineUpgradeCubit,
            ),
          ],
          child: Overlay(
            initialEntries: [
              OverlayEntry(builder: (context) => const SettingsScreen()),
            ],
          ),
        ),
      ),
    );
  }

  group('SettingsScreen model-phase rows (AIO-3000)', () {
    testWidgets('renders a Task Review Model row, with its description, '
        'directly after the Execution Model row', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final executionLabel = find.text(l10n.settingsModelExecutionLabel);
      final taskVerifyLabel = find.text(l10n.settingsModelTaskVerifyLabel);
      final contextCapLabel = find.text(l10n.settingsExecutionContextCapLabel);

      expect(taskVerifyLabel, findsOneWidget);
      expect(
        find.text(l10n.settingsModelTaskVerifyDescription),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(executionLabel).dy,
        lessThan(tester.getTopLeft(taskVerifyLabel).dy),
      );
      // Context cap is held in Loading here, so it may not render; only
      // assert ordering against it when it does.
      if (contextCapLabel.evaluate().isNotEmpty) {
        expect(
          tester.getTopLeft(taskVerifyLabel).dy,
          lessThan(tester.getTopLeft(contextCapLabel).dy),
        );
      }
    });

    testWidgets("the Task Review row shows taskVerify's own routed model, "
        "independent of execution's", (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      // Execution (and frontier/capable) route to the cheap model; only the
      // taskVerify row should show the strong reviewer.
      expect(find.text(_reviewModel.label), findsOneWidget);
      expect(find.text(_executionModel.label), findsNWidgets(3));
    });
  });
}
