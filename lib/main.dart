// main.dart — App entry point: database init, repository/BLoC providers, theme, router.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/l10n/generated/app_localizations.dart';
import 'package:aion/features/tickets/data/repositories/drift_comment_repository.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_link_repository.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_repository.dart';
import 'package:aion/features/tickets/tickets.dart';

/// App entry point. Opens the [AppDatabase], fires off a best-effort
/// trash purge, and runs [AionApp].
void main() {
  final database = AppDatabase();
  unawaited(_purgeOldTrashOnLaunch(database));
  runApp(AionApp(database: database));
}

/// Permanently purges trashed tickets older than
/// [TrashCubit.purgeAgeThreshold] on every cold start, so trash is
/// cleaned up even for users who never visit the Trash screen's manual
/// "Purge old" action. Fire-and-forget: [main] does not await this, so
/// it never delays first paint. Failures are swallowed — a missed purge
/// has no user-visible consequence and simply gets another chance on
/// the next launch.
Future<void> _purgeOldTrashOnLaunch(AppDatabase database) async {
  try {
    await DriftTicketRepository(
      database,
    ).purgeTrashOlderThan(TrashCubit.purgeAgeThreshold);
  } catch (_) {
    // Best-effort housekeeping — no user-facing surface for failures,
    // and this codebase has no logging infrastructure to report into.
  }
}

/// The Aion app root. Wires repository providers, the root-level
/// [TicketsCubit], [ThemeScope] (tracking system brightness), and the
/// `WidgetsApp.router` shell — no `MaterialApp`, no `ThemeData`.
class AionApp extends StatefulWidget {
  /// Creates the [AionApp] root widget, backed by [database].
  const AionApp({super.key, required this.database});

  /// The already-opened database, shared by all repositories.
  final AppDatabase database;

  @override
  State<AionApp> createState() => _AionAppState();
}

class _AionAppState extends State<AionApp> with WidgetsBindingObserver {
  late AionThemeData _theme;

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
        RepositoryProvider<TicketRepository>(
          create: (_) => DriftTicketRepository(widget.database),
        ),
        RepositoryProvider<CommentRepository>(
          create: (_) => DriftCommentRepository(widget.database),
        ),
        RepositoryProvider<TicketLinkRepository>(
          create: (_) => DriftTicketLinkRepository(widget.database),
        ),
      ],
      child: BlocProvider<TicketsCubit>(
        create: (context) => TicketsCubit(context.read<TicketRepository>()),
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
