// test/features/tickets/presentation/widgets/ticket_metadata_section_test.dart — TicketMetadataSection widget tests.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_link_picker.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_metadata_section.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockTicketsCubit extends MockCubit<TicketsState>
    implements TicketsCubit {}

class MockTicketLinkRepository extends Mock implements TicketLinkRepository {}

/// Wraps [ticket] in a [TicketMetadataSection], backed by a
/// [MockTicketsCubit] fixed to a [TicketDetailLoaded] state for [ticket]
/// (plus [linkedTickets]). `TicketLinkRepository` is no longer read
/// directly by this section (T14: creation/removal/retype all go through
/// `TicketsCubit` now — see `ticket_metadata_section.dart`'s class doc),
/// so it's provided here only because `TicketLinkPicker`'s ancestor
/// widget tree doesn't otherwise need it — kept as an unused stub
/// provider for parity with any sibling widget that still expects one.
/// Mirrors `tickets_board_view_test.dart`'s `_wrap` shape — a
/// `WidgetsApp` with `home` (not `builder`), so the Overlay
/// `TicketLinkPicker`/`SelectionMenu` need is present.
Widget _wrap({
  required Ticket ticket,
  required MockTicketsCubit ticketsCubit,
  List<LinkedTicketRef> linkedTickets = const [],
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
  );
}

void main() {
  late MockTicketsCubit ticketsCubit;

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

    when(
      () => ticketsCubit.getAllTickets(),
    ).thenAnswer((_) async => [candidateEpic]);
    // TicketParentPicker (rendered for every non-epic type) eagerly
    // loads its candidates in initState.
    when(
      () => ticketsCubit.getValidParentCandidates(any()),
    ).thenAnswer((_) async => []);
    when(
      () => ticketsCubit.createTicketLink(any(), any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => ticketsCubit.deleteTicketLink(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => ticketsCubit.updateTicketLinkType(any(), any(), any()),
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

    await tester.pumpWidget(_wrap(ticket: epic, ticketsCubit: ticketsCubit));
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

    await tester.pumpWidget(_wrap(ticket: story, ticketsCubit: ticketsCubit));
    await tester.pumpAndSettle();

    expect(find.text('LINKED TICKETS'), findsOneWidget);
  });

  testWidgets(
    'a task ticket now renders the Linked Tickets section, and selecting '
    'Blocks from the picker calls TicketsCubit.createTicketLink with that '
    'exact type, not relatesTo (board-task-ordering-indication)',
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

      await tester.pumpWidget(_wrap(ticket: task, ticketsCubit: ticketsCubit));
      await tester.pumpAndSettle();

      expect(find.text('LINKED TICKETS'), findsOneWidget);

      // Scoped to `TicketLinkPicker`'s own trigger — the new
      // `GapsAndOpenQuestionsSection` (idea-gap-question-ticket-types)
      // renders a second "Add" button (its `RaiseGapOrQuestionPicker`
      // trigger) alongside it.
      final linkedTicketsAdd = find.descendant(
        of: find.byType(TicketLinkPicker),
        matching: find.text('Add'),
      );
      await tester.ensureVisible(linkedTicketsAdd);
      await tester.pumpAndSettle();
      await tester.tap(linkedTicketsAdd);
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
        () => ticketsCubit.createTicketLink(
          task.id,
          candidateEpic.id,
          TicketLinkType.blocks,
        ),
      ).called(1);
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
        _wrap(ticket: resource, ticketsCubit: ticketsCubit),
      );
      await tester.pumpAndSettle();

      expect(find.text('LINKED TICKETS'), findsOneWidget);

      // Scoped to `TicketLinkPicker`'s own trigger — see the equivalent
      // comment in the task-ticket test above.
      final linkedTicketsAdd = find.descendant(
        of: find.byType(TicketLinkPicker),
        matching: find.text('Add'),
      );
      await tester.ensureVisible(linkedTicketsAdd);
      await tester.pumpAndSettle();
      await tester.tap(linkedTicketsAdd);
      await tester.pumpAndSettle();

      // No link-type selector row for resource — a single-tap flow.
      expect(find.text('Relates to'), findsNothing);

      await tester.ensureVisible(find.text('A candidate epic'));
      await tester.tap(find.text('A candidate epic'));
      await tester.pumpAndSettle();

      verify(
        () => ticketsCubit.createTicketLink(
          resource.id,
          candidateEpic.id,
          TicketLinkType.relatesTo,
        ),
      ).called(1);
    },
  );

  group('row remove/retype actions (ticket-link-management-ui)', () {
    late Ticket task;
    late LinkedTicketRef linkedRef;

    setUp(() {
      task = Ticket(
        id: 'task-1',
        ticketId: 'AIO-3',
        type: TicketType.task,
        title: 'A Task',
        status: TicketStatus.todo,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      linkedRef = (
        ticket: candidateEpic,
        relativeType: TicketLinkType.blockedBy,
        linkId: 'link-1',
      );
    });

    testWidgets(
      "a row's TicketsCubit.updateTicketLinkType call carries the row's "
      'link id and the newly picked relative type',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            ticket: task,
            ticketsCubit: ticketsCubit,
            linkedTickets: [linkedRef],
          ),
        );
        await tester.pumpAndSettle();

        // The row's action buttons are only revealed on hover — simulated
        // here by directly invoking the callback `LinkedTicketsSection`
        // wires, exercised more directly in
        // `linked_tickets_section_test.dart`. This test only asserts the
        // call site's own wiring: `ticket_metadata_section.dart` must
        // pass the callback through to `TicketsCubit` unmodified.
        final section = tester.widget<LinkedTicketsSection>(
          find.byType(LinkedTicketsSection),
        );
        section.onChangeType('link-1', TicketLinkType.blocks);

        verify(
          () => ticketsCubit.updateTicketLinkType(
            task.id,
            'link-1',
            TicketLinkType.blocks,
          ),
        ).called(1);
      },
    );

    testWidgets(
      "a row's TicketsCubit.deleteTicketLink call carries the row's link id",
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            ticket: task,
            ticketsCubit: ticketsCubit,
            linkedTickets: [linkedRef],
          ),
        );
        await tester.pumpAndSettle();

        final section = tester.widget<LinkedTicketsSection>(
          find.byType(LinkedTicketsSection),
        );
        section.onRemove('link-1');

        verify(
          () => ticketsCubit.deleteTicketLink(task.id, 'link-1'),
        ).called(1);
      },
    );
  });

  group(
    'AI suggestion badge / regenerate button '
    '(ai-assisted-complexity-and-estimate-suggestions)',
    () {
      Ticket sizedTask({
        TicketEstimationSource? complexitySource,
        TicketEstimationSource? estimateSource,
      }) => Ticket(
        id: 'task-ai',
        ticketId: 'AIO-9',
        type: TicketType.task,
        title: 'AI-sized task',
        status: TicketStatus.todo,
        complexity: TicketComplexity.medium,
        estimate: 60,
        complexitySource: complexitySource,
        estimateSource: estimateSource,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      setUp(() {
        when(
          () => ticketsCubit.regenerateComplexitySuggestion(any()),
        ).thenAnswer((_) async {});
        when(
          () => ticketsCubit.regenerateEstimateSuggestion(any()),
        ).thenAnswer((_) async {});
      });

      testWidgets('renders the plain badge for an aiSuggested complexity, '
          'no regenerate button', (tester) async {
        final task = sizedTask(
          complexitySource: TicketEstimationSource.aiSuggested,
        );
        await tester.pumpWidget(_wrap(ticket: task, ticketsCubit: ticketsCubit));
        await tester.pumpAndSettle();

        expect(find.byType(AiSuggestionBadge), findsOneWidget);
        expect(find.text('AI suggested'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Regenerate complexity suggestion'),
          findsNothing,
        );
      });

      testWidgets('renders the low-confidence badge (with caveat) for an '
          'aiSuggestedLowConfidence complexity', (tester) async {
        final task = sizedTask(
          complexitySource: TicketEstimationSource.aiSuggestedLowConfidence,
        );
        await tester.pumpWidget(_wrap(ticket: task, ticketsCubit: ticketsCubit));
        await tester.pumpAndSettle();

        expect(find.byType(AiSuggestionBadge), findsOneWidget);
        expect(find.textContaining('low confidence'), findsOneWidget);
      });

      testWidgets('renders the regenerate button (not a badge) for a '
          'manual-locked complexity, and tapping it calls '
          'regenerateComplexitySuggestion', (tester) async {
        final task = sizedTask(
          complexitySource: TicketEstimationSource.manual,
        );
        await tester.pumpWidget(_wrap(ticket: task, ticketsCubit: ticketsCubit));
        await tester.pumpAndSettle();

        expect(find.byType(AiSuggestionBadge), findsNothing);
        final button = find.bySemanticsLabel(
          'Regenerate complexity suggestion',
        );
        expect(button, findsOneWidget);

        await tester.tap(button);
        await tester.pumpAndSettle();

        verify(
          () => ticketsCubit.regenerateComplexitySuggestion(task),
        ).called(1);
      });

      testWidgets('renders the regenerate button (not a badge) for a '
          'manual-locked estimate, and tapping it calls '
          'regenerateEstimateSuggestion', (tester) async {
        final task = sizedTask(estimateSource: TicketEstimationSource.manual);
        await tester.pumpWidget(_wrap(ticket: task, ticketsCubit: ticketsCubit));
        await tester.pumpAndSettle();

        final button = find.bySemanticsLabel('Regenerate estimate suggestion');
        expect(button, findsOneWidget);

        await tester.tap(button);
        await tester.pumpAndSettle();

        verify(
          () => ticketsCubit.regenerateEstimateSuggestion(task),
        ).called(1);
      });

      testWidgets('renders no badge/button when the source is unset '
          '(manual write path, not covered by this feature)', (tester) async {
        final task = sizedTask();
        await tester.pumpWidget(_wrap(ticket: task, ticketsCubit: ticketsCubit));
        await tester.pumpAndSettle();

        expect(find.byType(AiSuggestionBadge), findsNothing);
        expect(
          find.bySemanticsLabel('Regenerate complexity suggestion'),
          findsNothing,
        );
        expect(
          find.bySemanticsLabel('Regenerate estimate suggestion'),
          findsNothing,
        );
      });
    },
  );
}
