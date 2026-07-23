// main.dart — App entry point: registry database init, root providers, theme, router.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/l10n/generated/app_localizations.dart';
import 'package:aion/features/projects/data/repositories/bundled_baseline_repository.dart';
import 'package:aion/features/projects/data/repositories/drift_project_repository.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/providers/data/repositories/shared_prefs_model_routing_repository.dart';
import 'package:aion/features/providers/providers.dart';

/// App entry point. No [AppDatabase] is opened here — it no longer has
/// one fixed global location; each project opens its own instance once
/// active (see `WorkspaceShell` in `core/routing/app_router.dart`, and
/// `aion-arch/changes/multi-project-hub/design.md` §6, §7). Only the
/// non-project-scoped [RegistryDatabase] (owned by [AionApp]) exists at
/// launch.
void main() {
  runApp(const AionApp());
}

/// The Aion app root. Wires the [RegistryDatabase] and its repositories,
/// [ActiveProjectCubit], [ThemeScope] (tracking system brightness), the
/// app-level provider-configuration stack ([AgentBridgeLocator],
/// [AgentModelClient], [ModelRoutingRepository] — global, not
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
        // setting — see aion-arch/changes/provider-configuration/design.md
        // §5. Desktop-only (ClaudeAgentSdkClient spawns a Node subprocess);
        // still safe to construct on any platform, since construction
        // itself does no I/O.
        RepositoryProvider<AgentBridgeLocator>(
          create: (_) => AgentBridgeLocator(),
        ),
        RepositoryProvider<AgentModelClient>(
          create: (context) =>
              ClaudeAgentSdkClient(context.read<AgentBridgeLocator>()),
        ),
        RepositoryProvider<ModelRoutingRepository>(
          create: (_) => SharedPrefsModelRoutingRepository(),
        ),
        // Global (not per-project) SDD-stage-triggering confidence
        // setting — see aion-arch/changes/sdd-ticket-execution/design.md.
        RepositoryProvider<AutomationSettingsRepository>(
          create: (_) => SharedPrefsAutomationSettingsRepository(),
        ),
      ],
      child: BlocProvider<ActiveProjectCubit>(
        create: (context) =>
            ActiveProjectCubit(context.read<ProjectRepository>()),
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
    );
  }
}
