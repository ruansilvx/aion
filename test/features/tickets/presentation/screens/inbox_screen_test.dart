// test/features/tickets/presentation/screens/inbox_screen_test.dart — InboxScreen widget tests.

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockInboxCubit extends MockCubit<InboxState> implements InboxCubit {}

Ticket _historyChat({
  required String id,
  required InboxPurpose purpose,
  String title = 'A past Inbox chat',
}) {
  return Ticket(
    id: id,
    ticketId: 'AIO-$id',
    type: TicketType.chat,
    title: title,
    status: TicketStatus.backlog,
    inboxPurpose: purpose,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

/// Wraps [InboxScreen] with a real [GoRouter] (`/workspace/inbox` plus a
/// `/workspace/tickets/:id` stand-in so navigation can be observed) and
/// the given [cubit].
Widget _wrap(InboxCubit cubit) {
  final router = GoRouter(
    initialLocation: '/workspace/inbox',
    routes: [
      GoRoute(
        path: '/workspace/inbox',
        builder: (context, state) => BlocProvider<InboxCubit>.value(
          value: cubit,
          child: const InboxScreen(),
        ),
      ),
      GoRoute(
        path: '/workspace/tickets/:id',
        builder: (context, state) =>
            Text('Ticket detail: ${state.pathParameters['id']}'),
      ),
    ],
  );

  return MediaQuery(
    data: const MediaQueryData(size: Size(1000, 1400)),
    child: ThemeScope(
      theme: aionThemeArctic,
      child: WidgetsApp.router(
        routerConfig: router,
        color: aionThemeArctic.colors.primary,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
}

void main() {
  late MockInboxCubit cubit;

  setUp(() {
    cubit = MockInboxCubit();
    // Not InboxInitial/InboxLoading — those render AppSpinner, whose
    // animation never settles and would hang every pumpAndSettle call
    // below. Individual tests override this via `when(() =>
    // cubit.state)` where the loading/empty/populated state itself is
    // what's under test.
    when(() => cubit.state).thenReturn(const InboxLoaded(history: []));
    when(
      () => cubit.stream,
    ).thenAnswer((_) => const Stream<InboxState>.empty());
    when(() => cubit.load()).thenAnswer((_) async {});
  });

  testWidgets('calls load() on init', (tester) async {
    await tester.pumpWidget(_wrap(cubit));
    await tester.pump();

    verify(() => cubit.load()).called(1);
  });

  testWidgets(
    'tapping "What\'s next" calls startWhatNextGuidance and navigates to '
    'the returned ticket',
    (tester) async {
      when(
        () => cubit.startWhatNextGuidance(),
      ).thenAnswer((_) async => 'chat-123');

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      await tester.tap(find.text("What's next"));
      await tester.pumpAndSettle();

      verify(() => cubit.startWhatNextGuidance()).called(1);
      expect(find.text('Ticket detail: chat-123'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping "Plan a release" calls startReleasePlanning and navigates to '
    'the returned ticket',
    (tester) async {
      when(
        () => cubit.startReleasePlanning(),
      ).thenAnswer((_) async => 'chat-456');

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      await tester.tap(find.text('Plan a release'));
      await tester.pumpAndSettle();

      verify(() => cubit.startReleasePlanning()).called(1);
      expect(find.text('Ticket detail: chat-456'), findsOneWidget);
    },
  );

  testWidgets(
    'a one-tap purpose that returns null does not navigate',
    (tester) async {
      when(() => cubit.startWhatNextGuidance()).thenAnswer((_) async => null);

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      await tester.tap(find.text("What's next"));
      await tester.pumpAndSettle();

      expect(find.byType(InboxScreen), findsOneWidget);
    },
  );

  testWidgets(
    'expanding "Brain dump", typing, and tapping submit calls '
    'startBrainDump with the typed text and navigates on success',
    (tester) async {
      when(
        () => cubit.startBrainDump(any()),
      ).thenAnswer((_) async => 'chat-789');

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      await tester.tap(find.text('Brain dump'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'idea one\nidea two');
      await tester.pump();

      await tester.tap(find.text('Create tickets'));
      await tester.pumpAndSettle();

      verify(() => cubit.startBrainDump('idea one\nidea two')).called(1);
      expect(find.text('Ticket detail: chat-789'), findsOneWidget);
    },
  );

  testWidgets(
    'the brain-dump submit button is disabled until text is entered',
    (tester) async {
      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      await tester.tap(find.text('Brain dump'));
      await tester.pumpAndSettle();

      // The submit button is IgnorePointer-wrapped while disabled — this
      // tap is expected to miss.
      await tester.tap(find.text('Create tickets'), warnIfMissed: false);
      await tester.pumpAndSettle();

      verifyNever(() => cubit.startBrainDump(any()));
    },
  );

  testWidgets(
    'expanding "Ask a question", typing, and tapping submit calls '
    'startQa and navigates on success',
    (tester) async {
      when(() => cubit.startQa(any())).thenAnswer((_) async => 'chat-qa-1');

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      await tester.tap(find.text('Ask a question'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'How does auth work?');
      await tester.pump();

      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();

      verify(() => cubit.startQa('How does auth work?')).called(1);
      expect(find.text('Ticket detail: chat-qa-1'), findsOneWidget);
    },
  );

  testWidgets(
    'renders an InboxHistoryItem per entry when history is populated',
    (tester) async {
      when(() => cubit.state).thenReturn(
        InboxLoaded(
          history: [
            _historyChat(id: '1', purpose: InboxPurpose.qa, title: 'Q&A one'),
            _historyChat(
              id: '2',
              purpose: InboxPurpose.brainDump,
              title: 'Dump one',
            ),
          ],
        ),
      );

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(find.byType(InboxHistoryItem), findsNWidgets(2));
      expect(find.byType(InboxEmptyState), findsNothing);
    },
  );

  testWidgets('renders InboxEmptyState when history is empty', (
    tester,
  ) async {
    when(
      () => cubit.state,
    ).thenReturn(const InboxLoaded(history: []));

    await tester.pumpWidget(_wrap(cubit));
    await tester.pump();

    expect(find.byType(InboxEmptyState), findsOneWidget);
    expect(find.byType(InboxHistoryItem), findsNothing);
  });

  testWidgets('tapping a history item navigates to its ticket detail', (
    tester,
  ) async {
    when(() => cubit.state).thenReturn(
      InboxLoaded(
        history: [_historyChat(id: '42', purpose: InboxPurpose.qa)],
      ),
    );

    await tester.pumpWidget(_wrap(cubit));
    await tester.pump();

    await tester.tap(find.byType(InboxHistoryItem));
    await tester.pumpAndSettle();

    expect(find.text('Ticket detail: 42'), findsOneWidget);
  });

  testWidgets('an InboxError state shows an AppToast with its message', (
    tester,
  ) async {
    final controller = StreamController<InboxState>.broadcast();
    addTearDown(controller.close);
    when(() => cubit.stream).thenAnswer((_) => controller.stream);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pump();

    controller.add(const InboxError('Something went wrong'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Something went wrong'), findsOneWidget);

    // Lets AppToast's own auto-dismiss Future.delayed fire so no pending
    // Timer trips flutter_test's post-test leftover-timer check.
    await tester.pump(const Duration(seconds: 4));
  });
}
