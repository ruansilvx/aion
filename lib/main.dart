// main.dart — App entry point: registry database init, root providers, theme, router.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:aion/core/agent/anthropic_messages_api_client.dart';
import 'package:aion/core/agent/anthropic_messages_api_provider.dart';
import 'package:aion/core/build/project_stack_detector.dart';
import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/l10n/generated/app_localizations.dart';
import 'package:aion/features/projects/data/repositories/bundled_baseline_repository.dart';
import 'package:aion/features/projects/data/repositories/drift_project_repository.dart';
import 'package:aion/features/projects/data/services/baseline_tailoring_service.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/providers/data/repositories/secure_storage_anthropic_api_key_repository.dart';
import 'package:aion/features/providers/data/repositories/shared_prefs_execution_context_cap_repository.dart';
import 'package:aion/features/providers/data/repositories/shared_prefs_execution_scheduling_repository.dart';
import 'package:aion/features/providers/data/repositories/shared_prefs_model_routing_repository.dart';
import 'package:aion/features/providers/providers.dart';

/// App entry point. No [AppDatabase] is opened here — it no longer has one
/// fixed global location; each project opens its own instance once active (see
/// `WorkspaceShell` in `core/routing/app_router.dart`, and `AIO-1174` §6, §7).
/// Only the non-project-scoped [RegistryDatabase] (owned by [AionApp]) exists
/// at launch.
void main() {
  runApp(const AionApp());
}

/// The Aion app root. Wires the [RegistryDatabase] and its repositories,
/// [ActiveProjectCubit], [ThemeScope] (tracking system brightness), the
/// app-level provider-configuration stack ([AgentBridgeLocator],
/// [ProviderRegistry], [ModelRoutingRepository] — global, not
/// per-project, since per-phase model routing isn't a per-project
/// concept), [AutomationSettingsRepository] (also global — SDD-stage-
/// triggering confidence isn't a per-project concept either), and the
/// `WidgetsApp.router` shell — no `MaterialApp`, no `ThemeData`.
/// Project-scoped state (ticket repositories, [AppDatabase]) is wired
/// per-project inside `WorkspaceShell`, not here.
class AionApp extends StatefulWidget {
  /// Creates the [AionApp] root widget.
  const AionApp({super.key});

  @override
  State<AionApp> createState() => _AionAppState();
}

class _AionAppState extends State<AionApp> with WidgetsBindingObserver {
  late AionThemeData _theme;
  late final RegistryDatabase _registryDatabase = RegistryDatabase();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _theme = _themeForBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_registryDatabase.close());
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {
      _theme = _themeForBrightness(
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
      );
    });
  }

  AionThemeData _themeForBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? aionThemeObsidian : aionThemeArctic;
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ProjectRepository>(
          create: (_) => DriftProjectRepository(_registryDatabase),
        ),
        RepositoryProvider<BaselineRepository>(
          create: (context) =>
              BundledBaselineRepository(context.read<ProjectRepository>()),
        ),
        // Project-agnostic (a bundled, on-device model, not addressed to
        // any project's rootPath) — unlike the ticket git-sync services
        // in WorkspaceShell, which do need a project's rootPath and are
        // wired there instead.
        RepositoryProvider<EmbeddingProvider>(
          create: (_) => BundledEmbeddingProvider(),
        ),
        // Provider identity/model selection is a global (not per-project)
        // setting — see AIO-1699 §5. Desktop-only (ClaudeAgentSdkClient spawns
        // a Node subprocess); still safe to construct on any platform, since
        // construction itself does no I/O. ProviderRegistry is where a second
        // provider gets registered — see AIO-1544 §1, §8 and AIO-110 §10.
        RepositoryProvider<AgentBridgeLocator>(
          create: (_) => AgentBridgeLocator(),
        ),
        // The Anthropic Messages API provider's own dependencies — a plain
        // shared `Dio` instance, and the secure-storage-backed API key
        // repository. See AIO-110 §10.
        RepositoryProvider<Dio>(create: (_) => Dio()),
        RepositoryProvider<AnthropicApiKeyRepository>(
          create: (_) => SecureStorageAnthropicApiKeyRepository(
            const FlutterSecureStorage(),
          ),
        ),
        RepositoryProvider<ProviderRegistry>(
          create: (context) => StaticProviderRegistry([
            ClaudeAgentSdkProvider(context.read<AgentBridgeLocator>()),
            AnthropicMessagesApiProvider(
              AnthropicMessagesApiClient(
                context.read<Dio>(),
                () => context.read<AnthropicApiKeyRepository>().getApiKey(),
              ),
            ),
          ]),
        ),
        RepositoryProvider<ModelRoutingRepository>(
          create: (context) =>
              SharedPrefsModelRoutingRepository(context.read<ProviderRegistry>()),
        ),
        // The coding-execution context-window handoff cap override — also
        // global, mirroring ModelRoutingRepository's own scope. Added for
        // AIO-833.
        RepositoryProvider<ExecutionContextCapRepository>(
          create: (_) => SharedPrefsExecutionContextCapRepository(),
        ),
        // The coding-execution scheduling mode/concurrency-ceiling choice —
        // also global, mirroring ExecutionContextCapRepository's own scope.
        // Added for `AIO-1400`.
        RepositoryProvider<ExecutionSchedulingRepository>(
          create: (_) => SharedPrefsExecutionSchedulingRepository(),
        ),
        // Global (not per-project) SDD-stage-triggering confidence setting —
        // see AIO-1856.
        RepositoryProvider<AutomationSettingsRepository>(
          create: (_) => SharedPrefsAutomationSettingsRepository(),
        ),
      ],
      child: BlocProvider<ActiveProjectCubit>(
        create: (context) => ActiveProjectCubit(
          context.read<ProjectRepository>(),
          context.read<BaselineRepository>(),
          BaselineTailoringService(
            context.read<BaselineRepository>(),
            ProjectStackDetector(),
          ),
        ),
        child: RepositoryProvider<ActiveProjectProvider>(
          // Exposes the same ActiveProjectCubit instance under its
          // core/contracts/ interface type too, so any feature can
          // `context.read<ActiveProjectProvider>()` per project.md's Pattern 1
          // without importing features/projects/ directly —
          // BlocProvider<ActiveProjectCubit> alone only registers under the
          // concrete ActiveProjectCubit type. Added for AIO-1266.
          create: (context) => context.read<ActiveProjectCubit>(),
          child: ThemeScope(
            theme: _theme,
            child: WidgetsApp.router(
              routerConfig: appRouter,
              color: aionThemeArctic.colors.primary,
              // TextField (the sole permitted Material widget, see design.md
              // Material Coupling Audit) reads MaterialLocalizations
              // internally regardless of MaterialApp/Scaffold usage.
              // AppLocalizations.delegate is generated (see l10n.yaml) and
              // resolves context.l10n (core/localization/context_localizations_x.dart)
              // for every user-facing string in the app.
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        ),
      ),
    );
  }
}
