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
/// [ActiveProjectCubit], [ThemeScope] (tracking system brightness), and
/// the `WidgetsApp.router` shell — no `MaterialApp`, no `ThemeData`.
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
