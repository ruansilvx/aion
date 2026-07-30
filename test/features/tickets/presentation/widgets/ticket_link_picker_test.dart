// test/features/tickets/presentation/widgets/ticket_link_picker_test.dart — TicketLinkPicker widget tests.

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_link_picker.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

/// Wraps [child] with the providers/localization/theme/navigator
/// scaffolding [TicketLinkPicker] needs to build and open its overlay —
/// same shape as `tickets_board_view_test.dart`'s `_wrap`.
Widget _wrap(Widget child) {
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
        // Centered, on a generously oversized test surface (see `setUp`
        // below) — the search overlay panel extends left of its own
        // trigger, and the nested link-type menu extends right of *its*
        // trigger nested inside that panel, so centering with plenty of
        // margin on every side is simpler than reasoning about which
        // single corner keeps both nested overlays on-screen.
        home: Align(child: child),
      ),
    ),
  );
}

void main() {
  final candidate = Ticket(
    id: 'candidate-1',
    ticketId: 'AIO-1',
    type: TicketType.task,
    title: 'Candidate ticket',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUp(() {
    // TicketLinkPicker's overlay follows the trigger via
    // CompositedTransformFollower, anchored well below/right of it —
    // the default 800x600 test surface clips that overlay off-screen,
    // so hit-testing its content needs a taller viewport. devicePixelRatio
    // is pinned to 1 too, since physicalSize is in physical (not
    // logical) pixels.
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(2000, 2000);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets(
    'selecting a non-default TicketLinkType from the SelectionMenu before '
    'tapping a candidate row calls onSelected with that type, not the '
    'default relatesTo',
    (tester) async {
      Ticket? selectedTicket;
      TicketLinkType? selectedType;

      await tester.pumpWidget(
        _wrap(
          TicketLinkPicker(
            candidatesLoader: () async => [candidate],
            linkTypeOptions: const [
              TicketLinkType.blocks,
              TicketLinkType.blockedBy,
              TicketLinkType.relatesTo,
              TicketLinkType.duplicates,
            ],
            onSelected: (ticket, type) {
              selectedTicket = ticket;
              selectedType = type;
            },
          ),
        ),
      );
      await tester.pump();

      // Open the picker overlay.
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Default trigger label before any change.
      expect(find.text('Relates to'), findsOneWidget);

      // Open the link-type menu and pick "Blocks".
      await tester.tap(find.text('Relates to'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blocks'));
      await tester.pumpAndSettle();

      // Trigger now reflects the new selection.
      expect(find.text('Blocks'), findsOneWidget);

      // Tap the candidate row.
      await tester.tap(find.text('Candidate ticket'));
      await tester.pumpAndSettle();

      expect(selectedTicket, candidate);
      expect(selectedType, TicketLinkType.blocks);
    },
  );

  testWidgets('the picker offers exactly the types passed via linkTypeOptions, '
      'nothing else', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TicketLinkPicker(
          candidatesLoader: () async => [candidate],
          linkTypeOptions: const [
            TicketLinkType.relatesTo,
            TicketLinkType.blocks,
          ],
          onSelected: (_, _) {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Relates to'));
    await tester.pumpAndSettle();

    // Only the two supplied options are offered — "Relates to" no
    // longer appears in the menu itself (SelectionMenu excludes the
    // current value), but the other two restricted-out types must be
    // entirely absent.
    expect(find.text('Blocks'), findsOneWidget);
    expect(find.text('Blocked by'), findsNothing);
    expect(find.text('Duplicates'), findsNothing);
  });
}
