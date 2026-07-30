// test/features/tickets/presentation/widgets/ticket_metadata_section_test.dart — TicketMetadataSection widget tests.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_metadata_section.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockTicketsCubit extends MockCubit<TicketsState>
    implements TicketsCubit {}

class MockTicketLinkRepository extends Mock implements TicketLinkRepository {}

/// Wraps [ticket] in a [TicketMetadataSection], backed by a
/// [MockTicketsCubit] fixed to a [TicketDetailLoaded] state for [ticket]
/// (plus [linkedTickets]), and a [MockTicketLinkRepository] for the
/// Linked Tickets picker's `createLink` call. Mirrors
/// `tickets_board_view_test.dart`'s `_wrap` shape — a `WidgetsApp` with
/// `home` (not `builder`), so the Overlay `TicketLinkPicker`/
/// `SelectionMenu` need is present.
Widget _wrap({
  required Ticket ticket,
  required MockTicketsCubit ticketsCubit,
  required MockTicketLinkRepository linkRepository,
  List<Ticket> linkedTickets = const [],
}) {
  whenListen(
    ticketsCubit,
    Stream.value(TicketDetailLoaded(ticket, linkedTickets: linkedTickets)),
    initialState: TicketDetailLoaded(ticket, linkedTickets: linkedTickets),
  );

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
        // `home` (not `builder`) so WidgetsApp mounts a Navigator, whose
        // Overlay ancestor TicketLinkPicker's overlay entry requires.
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 700,
            child: RepositoryProvider<TicketLinkRepository>.value(
              value: linkRepository,
              child: BlocProvider<TicketsCubit>.value(
                value: ticketsCubit,
                child: SingleChildScrollView(
                  child: TicketMetadataSection(
                    ticket: ticket,
                    automationConfidence: null,
                    onAdvanceSddStage: (_) {},
                    onMaybeAutoAdvance: (_, _) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late MockTicketsCubit ticketsCubit;
  late MockTicketLinkRepository linkRepository;

  final candidateEpic = Ticket(
    id: 'candidate-epic',
    ticketId: 'AIO-99',
    type: TicketType.epic,
    title: 'A candidate epic',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(2000, 2000);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    registerFallbackValue(TicketLinkType.relatesTo);
    registerFallbackValue(candidateEpic);
    ticketsCubit = MockTicketsCubit();
    linkRepository = MockTicketLinkRepository();

    when(
      () => ticketsCubit.getAllTickets(),
    ).thenAnswer((_) async => [candidateEpic]);
    // TicketParentPicker (rendered for every non-epic type) eagerly
    // loads its candidates in initState.
    when(
      () => ticketsCubit.getValidParentCandidates(any()),
    ).thenAnswer((_) async => []);
    when(
      () => ticketsCubit.loadDocumentRelations(any()),
    ).thenAnswer((_) async {});
    when(
      () => ticketsCubit.refreshBlockedBoardState(),
    ).thenAnswer((_) async {});
    when(
      () => linkRepository.createLink(
        sourceTicketId: any(named: 'sourceTicketId'),
        targetTicketId: any(named: 'targetTicketId'),
        linkType: any(named: 'linkType'),
      ),
    ).thenAnswer((_) async {});
  });

  testWidgets('an epic ticket now renders the Linked Tickets section '
      '(board-task-ordering-indication)', (tester) async {
    final epic = Ticket(
      id: 'epic-1',
      ticketId: 'AIO-1',
      type: TicketType.epic,
      title: 'An Epic',
      status: TicketStatus.backlog,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      _wrap(
        ticket: epic,
        ticketsCubit: ticketsCubit,
        linkRepository: linkRepository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LINKED TICKETS'), findsOneWidget);
  });

  testWidgets('a story ticket now renders the Linked Tickets section '
      '(board-task-ordering-indication)', (tester) async {
    final story = Ticket(
      id: 'story-1',
      ticketId: 'AIO-2',
      type: TicketType.story,
      title: 'A Story',
      status: TicketStatus.backlog,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      _wrap(
        ticket: story,
        ticketsCubit: ticketsCubit,
        linkRepository: linkRepository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LINKED TICKETS'), findsOneWidget);
  });

  testWidgets(
    'a task ticket now renders the Linked Tickets section, and selecting '
    'Blocks from the picker calls createLink with that exact type, not '
    'relatesTo (board-task-ordering-indication)',
    (tester) async {
      final task = Ticket(
        id: 'task-1',
        ticketId: 'AIO-3',
        type: TicketType.task,
        title: 'A Task',
        status: TicketStatus.todo,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      await tester.pumpWidget(
        _wrap(
          ticket: task,
          ticketsCubit: ticketsCubit,
          linkRepository: linkRepository,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('LINKED TICKETS'), findsOneWidget);

      await tester.ensureVisible(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Default link type before any change.
      expect(find.text('Relates to'), findsOneWidget);

      await tester.ensureVisible(find.text('Relates to'));
      await tester.tap(find.text('Relates to'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Blocks'));
      await tester.tap(find.text('Blocks'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('A candidate epic'));
      await tester.tap(find.text('A candidate epic'));
      await tester.pumpAndSettle();

      verify(
        () => linkRepository.createLink(
          sourceTicketId: task.id,
          targetTicketId: candidateEpic.id,
          linkType: TicketLinkType.blocks,
        ),
      ).called(1);
      // A blocks/blockedBy link refreshes the Board's blocked-badge
      // state too (ticket_metadata_section.dart's onSelected).
      verify(() => ticketsCubit.refreshBlockedBoardState()).called(1);
    },
  );

  testWidgets(
    "resource's existing single-tap relatesTo behavior is unchanged — no "
    'picker step introduced for it (board-task-ordering-indication)',
    (tester) async {
      final resource = Ticket(
        id: 'resource-1',
        ticketId: 'AIO-4',
        type: TicketType.resource,
        title: 'A Resource',
        status: TicketStatus.backlog,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      await tester.pumpWidget(
        _wrap(
          ticket: resource,
          ticketsCubit: ticketsCubit,
          linkRepository: linkRepository,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('LINKED TICKETS'), findsOneWidget);

      await tester.ensureVisible(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // No link-type selector row for resource — a single-tap flow.
      expect(find.text('Relates to'), findsNothing);

      await tester.ensureVisible(find.text('A candidate epic'));
      await tester.tap(find.text('A candidate epic'));
      await tester.pumpAndSettle();

      verify(
        () => linkRepository.createLink(
          sourceTicketId: resource.id,
          targetTicketId: candidateEpic.id,
          linkType: TicketLinkType.relatesTo,
        ),
      ).called(1);
      // relatesTo never touches the blocked-badge refresh path.
      verifyNever(() => ticketsCubit.refreshBlockedBoardState());
    },
  );
}
