// test/features/tickets/presentation/widgets/ticket_overflow_menu_test.dart — TicketOverflowMenu widget tests.

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockTicketLinkRepository extends Mock implements TicketLinkRepository {}

/// Same wrapping shape as `ticket_link_picker_test.dart`'s `_wrap` — a
/// `WidgetsApp` with `home` (not `builder`) so a `Navigator`/`Overlay`
/// ancestor exists for both this widget's own overlay and the nested
/// `TicketLinkPicker`'s overlay inside the promote chooser.
Widget _wrap(Widget child, TicketsCubit cubit) {
  return MediaQuery(
    data: const MediaQueryData(),
    child: ThemeScope(
      theme: aionThemeArctic,
      child: WidgetsApp(
        color: aionThemeArctic.colors.primary,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
            PageRouteBuilder<T>(
              settings: settings,
              pageBuilder: (context, _, _) => builder(context),
            ),
        home: Align(
          child: BlocProvider<TicketsCubit>.value(value: cubit, child: child),
        ),
      ),
    ),
  );
}

void main() {
  late MockTicketRepository repository;
  late MockTicketLinkRepository linkRepository;
  late TicketsCubit cubit;

  final epic = Ticket(
    id: 'epic-1',
    ticketId: 'AIO-2',
    type: TicketType.epic,
    title: 'Existing epic',
    status: 'backlog',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final bug = Ticket(
    id: 'bug-1',
    ticketId: 'AIO-3',
    type: TicketType.bug,
    title: 'Existing bug',
    status: 'backlog',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  Ticket buildIdea({TicketType? suggestedType}) => Ticket(
    id: 'idea-1',
    ticketId: 'AIO-1',
    type: TicketType.idea,
    title: 'A raw idea',
    status: 'backlog',
    suggestedType: suggestedType,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUpAll(() {
    registerFallbackValue(
      Ticket(
        id: 'fallback',
        ticketId: '',
        type: TicketType.epic,
        title: '',
        status: 'backlog',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    registerFallbackValue(TicketLinkType.relatesTo);
  });

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(2000, 2000);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    repository = MockTicketRepository();
    linkRepository = MockTicketLinkRepository();
    cubit = TicketsCubit(repository, linkRepository: linkRepository);

    when(
      () => repository.getAllTickets(),
    ).thenAnswer((_) async => [epic, bug]);
    when(() => repository.createTicket(any())).thenAnswer((_) async {});
    when(() => repository.updateTicket(any())).thenAnswer((_) async {});
    when(
      () => repository.getTicketById(epic.id),
    ).thenAnswer((_) async => epic);
    when(
      () => repository.getTicketById('idea-1'),
    ).thenAnswer((_) async => buildIdea().copyWith(type: TicketType.knownGap));
    when(
      () => linkRepository.createLink(
        sourceTicketId: any(named: 'sourceTicketId'),
        targetTicketId: any(named: 'targetTicketId'),
        linkType: any(named: 'linkType'),
      ),
    ).thenAnswer((_) async {});
  });

  testWidgets(
    'tapping the trigger for an idea ticket shows both promote rows '
    'and the delete row',
    (tester) async {
      await tester.pumpWidget(
        _wrap(TicketOverflowMenu(ticket: buildIdea()), cubit),
      );
      await tester.pump();

      await tester.tap(find.byType(TicketOverflowMenu));
      await tester.pumpAndSettle();

      expect(find.text('Promote to Epic'), findsOneWidget);
      expect(find.text('Promote to Bug'), findsOneWidget);
      expect(find.text('Change to Known Gap'), findsOneWidget);
      expect(find.text('Change to Open Question'), findsOneWidget);
      expect(find.text('Delete ticket'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping "Change to Known Gap" opens a target picker; picking an '
    'existing ticket calls reclassifyIdea',
    (tester) async {
      await tester.pumpWidget(
        _wrap(TicketOverflowMenu(ticket: buildIdea()), cubit),
      );
      await tester.pump();

      await tester.tap(find.byType(TicketOverflowMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change to Known Gap'));
      await tester.pumpAndSettle();

      // No "create new" option in the reclassify target picker, unlike
      // the promote chooser.
      expect(find.text('Create new epic'), findsNothing);
      expect(find.text('Create new bug'), findsNothing);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Existing epic'));
      await tester.pumpAndSettle();

      final updated =
          verify(() => repository.updateTicket(captureAny())).captured;
      expect(updated, hasLength(1));
      expect((updated.first as Ticket).type, TicketType.knownGap);
      verify(
        () => linkRepository.createLink(
          sourceTicketId: 'idea-1',
          targetTicketId: epic.id,
          linkType: TicketLinkType.relatesTo,
        ),
      ).called(1);
    },
  );

  testWidgets(
    'an idea with suggestedType epic shows exactly one "SUGGESTED" pill',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          TicketOverflowMenu(ticket: buildIdea(suggestedType: TicketType.epic)),
          cubit,
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(TicketOverflowMenu));
      await tester.pumpAndSettle();

      expect(find.text('SUGGESTED'), findsOneWidget);
    },
  );

  testWidgets(
    'an idea with no suggestedType shows no "SUGGESTED" pill',
    (tester) async {
      await tester.pumpWidget(
        _wrap(TicketOverflowMenu(ticket: buildIdea()), cubit),
      );
      await tester.pump();

      await tester.tap(find.byType(TicketOverflowMenu));
      await tester.pumpAndSettle();

      expect(find.text('SUGGESTED'), findsNothing);
    },
  );

  testWidgets(
    'tapping "Promote to Epic" opens a chooser offering only epic '
    'candidates',
    (tester) async {
      await tester.pumpWidget(
        _wrap(TicketOverflowMenu(ticket: buildIdea()), cubit),
      );
      await tester.pump();

      await tester.tap(find.byType(TicketOverflowMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Promote to Epic'));
      await tester.pumpAndSettle();

      // Chooser header + "Create new epic" both render "Promote to
      // Epic"/"Create new epic" text; the root's own copy is gone since
      // the chooser replaced it.
      expect(find.text('Promote to Epic'), findsOneWidget);
      expect(find.text('Create new epic'), findsOneWidget);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Existing epic'), findsOneWidget);
      expect(find.text('Existing bug'), findsNothing);
    },
  );

  testWidgets(
    'tapping "Promote to Bug" opens a chooser offering only bug candidates',
    (tester) async {
      await tester.pumpWidget(
        _wrap(TicketOverflowMenu(ticket: buildIdea()), cubit),
      );
      await tester.pump();

      await tester.tap(find.byType(TicketOverflowMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Promote to Bug'));
      await tester.pumpAndSettle();

      expect(find.text('Promote to Bug'), findsOneWidget);
      expect(find.text('Create new bug'), findsOneWidget);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Existing bug'), findsOneWidget);
      expect(find.text('Existing epic'), findsNothing);
    },
  );

  testWidgets(
    'tapping "Create new bug" calls promoteIdea with targetType bug',
    (tester) async {
      await tester.pumpWidget(
        _wrap(TicketOverflowMenu(ticket: buildIdea()), cubit),
      );
      await tester.pump();

      await tester.tap(find.byType(TicketOverflowMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Promote to Bug'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create new bug'));
      await tester.pumpAndSettle();

      final created =
          verify(() => repository.createTicket(captureAny())).captured;
      expect(created, hasLength(1));
      expect((created.first as Ticket).type, TicketType.bug);
    },
  );
}
