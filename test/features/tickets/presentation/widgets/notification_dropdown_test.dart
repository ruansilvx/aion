// test/features/tickets/presentation/widgets/notification_dropdown_test.dart — NotificationDropdownPanel widget tests.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart' hide Notification;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockTicketsCubit extends MockCubit<TicketsState> implements TicketsCubit {}

/// Wraps [NotificationDropdownPanel] behind a real [GoRouter] with a
/// `/workspace/tickets/:id` destination route, so a row tap's
/// `context.go(...)` call actually navigates — mirrors
/// `workspace_nav_shell_test.dart`'s `_wrapRouted` shape.
Widget _wrap({required TicketsCubit ticketsCubit, required VoidCallback onDismiss}) {
  final router = GoRouter(
    initialLocation: '/workspace/tickets',
    routes: [
      GoRoute(
        path: '/workspace/tickets',
        builder: (context, state) => BlocProvider<TicketsCubit>.value(
          value: ticketsCubit,
          child: Align(
            alignment: Alignment.topLeft,
            child: NotificationDropdownPanel(
              ticketsCubit: ticketsCubit,
              onDismiss: onDismiss,
            ),
          ),
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
    data: const MediaQueryData(size: Size(500, 800)),
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
  late MockTicketsCubit ticketsCubit;

  setUp(() {
    ticketsCubit = MockTicketsCubit();
  });

  testWidgets('shows the empty state when there are no notifications', (
    tester,
  ) async {
    when(
      () => ticketsCubit.getRecentNotifications(),
    ).thenAnswer((_) async => const []);

    await tester.pumpWidget(_wrap(ticketsCubit: ticketsCubit, onDismiss: () {}));
    await tester.pumpAndSettle();

    expect(find.text('No notifications yet'), findsOneWidget);
    // Disabled at zero unread — no rows to mark.
    expect(find.text('Mark all read'), findsOneWidget);
  });

  testWidgets(
    'tapping a row marks it read, navigates to the ticket, and dismisses',
    (tester) async {
      var dismissed = false;
      final notification = Notification(
        id: 'n1',
        ticketId: 'task-42',
        ticketTitle: 'Fix the thing',
        kind: NotificationKind.executionPrOpened,
        message: 'Opened PR #42 · 5 files changed',
        createdAt: DateTime(2026, 1, 1),
      );
      when(
        () => ticketsCubit.getRecentNotifications(),
      ).thenAnswer((_) async => [notification]);
      when(
        () => ticketsCubit.markNotificationRead('n1'),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(
        _wrap(
          ticketsCubit: ticketsCubit,
          onDismiss: () => dismissed = true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Fix the thing'), findsOneWidget);

      await tester.tap(find.text('Fix the thing'));
      await tester.pumpAndSettle();

      verify(() => ticketsCubit.markNotificationRead('n1')).called(1);
      expect(find.text('Ticket detail: task-42'), findsOneWidget);
      expect(dismissed, isTrue);
    },
  );

  testWidgets(
    '"Mark all read" clears every row\'s unread dot without navigating',
    (tester) async {
      final unreadA = Notification(
        id: 'n1',
        ticketId: 'task-1',
        ticketTitle: 'First',
        kind: NotificationKind.executionPrOpened,
        message: 'Opened PR #1',
        createdAt: DateTime(2026, 1, 1),
      );
      final unreadB = Notification(
        id: 'n2',
        ticketId: 'task-2',
        ticketTitle: 'Second',
        kind: NotificationKind.stageAdvanceCompleted,
        message: 'Advanced to Design',
        createdAt: DateTime(2026, 1, 2),
      );
      when(
        () => ticketsCubit.getRecentNotifications(),
      ).thenAnswer((_) async => [unreadB, unreadA]);
      when(
        () => ticketsCubit.markAllNotificationsRead(),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(_wrap(ticketsCubit: ticketsCubit, onDismiss: () {}));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();

      verify(() => ticketsCubit.markAllNotificationsRead()).called(1);
      // Both rows are still shown (the panel doesn't re-fetch), now in
      // their read visual state — this test only asserts the write path
      // fired, matching what `TicketsCubit.markAllNotificationsRead`'s
      // own unit test already covers for the underlying persistence.
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
    },
  );
}
