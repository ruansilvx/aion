// test/design_system/molecules/linked_tickets_section_test.dart — LinkedTicketsSection widget tests.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/semantics.dart' show SemanticsBinding;
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

/// Wraps [child] in a `WidgetsApp` with `home` (not `builder`), so the
/// Overlay `_LinkTypeEditor`/remove-confirmation popover need is
/// present, mirroring `ticket_metadata_section_test.dart`'s `_wrap`.
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
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 500, child: child),
        ),
      ),
    ),
  );
}

Ticket _buildTicket({
  required String id,
  required TicketType type,
  String title = 'A linked ticket',
}) => Ticket(
  id: id,
  ticketId: 'AIO-$id',
  type: type,
  title: title,
  status: 'backlog',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

const _fullOptions = [
  TicketLinkType.blocks,
  TicketLinkType.blockedBy,
  TicketLinkType.relatesTo,
  TicketLinkType.duplicates,
];

/// Moves a real mouse pointer over [finder]'s center, so hover-revealed
/// content (`_LinkRow`'s edit/remove actions) becomes visible and
/// tappable — a plain `tester.tap` doesn't trigger `MouseRegion.onEnter`.
Future<void> _hoverOver(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(gesture.removePointer);
  await gesture.addPointer(location: Offset.zero);
  await tester.pump();
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pumpAndSettle();
}

void main() {
  late SemanticsHandle semanticsHandle;

  setUp(() {
    semanticsHandle = SemanticsBinding.instance.ensureSemantics();
  });

  tearDown(() {
    semanticsHandle.dispose();
  });

  testWidgets('renders each row\'s relative-type glyph/label', (
    tester,
  ) async {
    final linked = _buildTicket(
      id: 'l1',
      type: TicketType.task,
      title: 'Linked task',
    );
    final ref = (
      ticket: linked,
      relativeType: TicketLinkType.blockedBy,
      linkId: 'link-1',
    );

    await tester.pumpWidget(
      _wrap(
        LinkedTicketsSection(
          links: [ref],
          linkTypeOptions: _fullOptions,
          onTap: (_) {},
          onRemove: (_) {},
          onChangeType: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Linked task'), findsOneWidget);
    expect(find.text('Blocked by'), findsOneWidget);
  });

  testWidgets(
    'tapping remove then confirming calls onRemove with the row link id',
    (tester) async {
      String? removedLinkId;
      final linked = _buildTicket(
        id: 'l1',
        type: TicketType.task,
        title: 'Linked task',
      );
      final ref = (
        ticket: linked,
        relativeType: TicketLinkType.relatesTo,
        linkId: 'link-1',
      );

      await tester.pumpWidget(
        _wrap(
          LinkedTicketsSection(
            links: [ref],
            linkTypeOptions: const [TicketLinkType.relatesTo],
            onTap: (_) {},
            onRemove: (id) => removedLinkId = id,
            onChangeType: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _hoverOver(tester, find.text('Linked task'));

      await tester.tap(find.bySemanticsLabel('Remove link'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(removedLinkId, 'link-1');
    },
  );

  testWidgets(
    'canceling the remove confirmation does not call onRemove',
    (tester) async {
      var removeCalled = false;
      final linked = _buildTicket(
        id: 'l1',
        type: TicketType.task,
        title: 'Linked task',
      );
      final ref = (
        ticket: linked,
        relativeType: TicketLinkType.relatesTo,
        linkId: 'link-1',
      );

      await tester.pumpWidget(
        _wrap(
          LinkedTicketsSection(
            links: [ref],
            linkTypeOptions: const [TicketLinkType.relatesTo],
            onTap: (_) {},
            onRemove: (_) => removeCalled = true,
            onChangeType: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _hoverOver(tester, find.text('Linked task'));

      await tester.tap(find.bySemanticsLabel('Remove link'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(removeCalled, isFalse);
    },
  );

  testWidgets(
    "selecting a new type in the row's editor calls onChangeType with "
    '(linkId, newRelativeType)',
    (tester) async {
      String? changedLinkId;
      TicketLinkType? newType;
      final linked = _buildTicket(
        id: 'l1',
        type: TicketType.task,
        title: 'Linked task',
      );
      final ref = (
        ticket: linked,
        relativeType: TicketLinkType.relatesTo,
        linkId: 'link-1',
      );

      await tester.pumpWidget(
        _wrap(
          LinkedTicketsSection(
            links: [ref],
            linkTypeOptions: _fullOptions,
            onTap: (_) {},
            onRemove: (_) {},
            onChangeType: (id, type) {
              changedLinkId = id;
              newType = type;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _hoverOver(tester, find.text('Linked task'));

      await tester.tap(find.bySemanticsLabel('Change type'));
      await tester.pumpAndSettle();

      // The editor trigger now shows the row's current relative label —
      // tap it to open the menu of other options.
      await tester.tap(find.text('Relates to'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Blocks'));
      await tester.pumpAndSettle();

      expect(changedLinkId, 'link-1');
      expect(newType, TicketLinkType.blocks);
    },
  );

  testWidgets(
    'a row whose relativeType is duplicatedBy renders no edit control',
    (tester) async {
      final linked = _buildTicket(
        id: 'l1',
        type: TicketType.task,
        title: 'Linked task',
      );
      final ref = (
        ticket: linked,
        relativeType: TicketLinkType.duplicatedBy,
        linkId: 'link-1',
      );

      await tester.pumpWidget(
        _wrap(
          LinkedTicketsSection(
            links: [ref],
            linkTypeOptions: _fullOptions,
            onTap: (_) {},
            onRemove: (_) {},
            onChangeType: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Duplicated by'), findsOneWidget);

      await _hoverOver(tester, find.text('Linked task'));

      expect(find.bySemanticsLabel('Change type'), findsNothing);
      expect(find.bySemanticsLabel('Remove link'), findsOneWidget);
    },
  );

  testWidgets(
    "a row whose linkTypeOptions has only its own current type renders no "
    'edit control',
    (tester) async {
      final linked = _buildTicket(
        id: 'l1',
        type: TicketType.resource,
        title: 'A resource',
      );
      final ref = (
        ticket: linked,
        relativeType: TicketLinkType.relatesTo,
        linkId: 'link-1',
      );

      await tester.pumpWidget(
        _wrap(
          LinkedTicketsSection(
            links: [ref],
            linkTypeOptions: const [TicketLinkType.relatesTo],
            onTap: (_) {},
            onRemove: (_) {},
            onChangeType: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _hoverOver(tester, find.text('A resource'));

      expect(find.bySemanticsLabel('Change type'), findsNothing);
      expect(find.bySemanticsLabel('Remove link'), findsOneWidget);
    },
  );
}
