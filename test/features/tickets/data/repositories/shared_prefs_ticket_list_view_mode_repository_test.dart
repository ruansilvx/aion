// test/features/tickets/data/repositories/shared_prefs_ticket_list_view_mode_repository_test.dart
// — SharedPrefsTicketListViewModeRepository round-trip, key-isolation,
// default-null, and unparseable-name tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/tickets/data/repositories/shared_prefs_ticket_list_view_mode_repository.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_view_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsTicketListViewModeRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'getViewMode returns null when nothing has been saved yet',
      () async {
        final repository = SharedPrefsTicketListViewModeRepository();

        final mode = await repository.getViewMode('proj-1');

        expect(mode, isNull);
      },
    );

    test('setViewMode then getViewMode round-trips the selection', () async {
      final repository = SharedPrefsTicketListViewModeRepository();

      await repository.setViewMode('proj-1', TicketListViewMode.list);
      final read = await repository.getViewMode('proj-1');

      expect(read, TicketListViewMode.list);
    });

    test(
      'project-id-prefixed keys isolate two different projects from each '
      'other',
      () async {
        final repository = SharedPrefsTicketListViewModeRepository();

        await repository.setViewMode('proj-a', TicketListViewMode.list);
        await repository.setViewMode('proj-b', TicketListViewMode.board);

        final modeA = await repository.getViewMode('proj-a');
        final modeB = await repository.getViewMode('proj-b');

        expect(modeA, TicketListViewMode.list);
        expect(modeB, TicketListViewMode.board);
      },
    );

    test(
      'setViewMode overwrites a previously saved selection for the same '
      'project',
      () async {
        final repository = SharedPrefsTicketListViewModeRepository();
        await repository.setViewMode('proj-1', TicketListViewMode.list);

        await repository.setViewMode('proj-1', TicketListViewMode.board);
        final read = await repository.getViewMode('proj-1');

        expect(read, TicketListViewMode.board);
      },
    );

    test(
      'getViewMode returns null for a stored name that no longer matches '
      'a TicketListViewMode value',
      () async {
        SharedPreferences.setMockInitialValues({
          'ticket_list_view_mode.proj-1': 'someRemovedMode',
        });
        final repository = SharedPrefsTicketListViewModeRepository();

        final mode = await repository.getViewMode('proj-1');

        expect(mode, isNull);
      },
    );
  });
}
