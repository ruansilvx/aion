// test/features/tickets/presentation/widgets/inbox_history_item_test.dart — InboxHistoryItem widget tests.

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

Widget _wrap(Widget child) {
  return MediaQuery(
    data: const MediaQueryData(size: Size(400, 200)),
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
        builder: (context, _) => child,
      ),
    ),
  );
}

Ticket _inboxChat({required InboxPurpose purpose, String title = 'A chat'}) {
  return Ticket(
    id: '1',
    ticketId: 'AIO-1',
    type: TicketType.chat,
    title: title,
    status: TicketStatus.backlog,
    inboxPurpose: purpose,
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    updatedAt: DateTime.now(),
  );
}

void main() {
  testWidgets('renders the BRAIN DUMP badge for a brainDump chat', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        InboxHistoryItem(
          ticket: _inboxChat(purpose: InboxPurpose.brainDump),
        ),
      ),
    );

    expect(find.text('BRAIN DUMP'), findsOneWidget);
  });

  testWidgets("renders the WHAT'S NEXT badge for a whatNextGuidance chat", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        InboxHistoryItem(
          ticket: _inboxChat(purpose: InboxPurpose.whatNextGuidance),
        ),
      ),
    );

    expect(find.text("WHAT'S NEXT"), findsOneWidget);
  });

  testWidgets('renders the RELEASE badge for a releasePlanning chat', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        InboxHistoryItem(
          ticket: _inboxChat(purpose: InboxPurpose.releasePlanning),
        ),
      ),
    );

    expect(find.text('RELEASE'), findsOneWidget);
  });

  testWidgets('renders the Q&A badge for a qa chat', (tester) async {
    await tester.pumpWidget(
      _wrap(InboxHistoryItem(ticket: _inboxChat(purpose: InboxPurpose.qa))),
    );

    expect(find.text('Q&A'), findsOneWidget);
  });

  testWidgets('renders the chat title', (tester) async {
    await tester.pumpWidget(
      _wrap(
        InboxHistoryItem(
          ticket: _inboxChat(purpose: InboxPurpose.qa, title: 'How does X work?'),
        ),
      ),
    );

    expect(find.text('How does X work?'), findsOneWidget);
  });

  testWidgets('tapping the row invokes onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        InboxHistoryItem(
          ticket: _inboxChat(purpose: InboxPurpose.brainDump),
          onTap: () => tapped = true,
        ),
      ),
    );

    await tester.tap(find.byType(InboxHistoryItem));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
