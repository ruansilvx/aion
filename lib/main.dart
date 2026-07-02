import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/core/routing/app_router.dart';
import 'package:aion/core/theme/aion_theme.dart';
import 'package:aion/core/theme/theme_scope.dart';
import 'package:aion/features/tickets/data/repositories/drift_comment_repository.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_link_repository.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_repository.dart';
import 'package:aion/features/tickets/domain/repositories/comment_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_link_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';

void main() {
  final database = AppDatabase();
  runApp(AionApp(database: database));
}

class AionApp extends StatefulWidget {
  const AionApp({super.key, required this.database});

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
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en', 'US')],
          ),
        ),
      ),
    );
  }
}
