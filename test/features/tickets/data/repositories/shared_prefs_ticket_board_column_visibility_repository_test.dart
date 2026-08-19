// test/features/tickets/data/repositories/shared_prefs_ticket_board_column_visibility_repository_test.dart
// — SharedPrefsTicketBoardColumnVisibilityRepository round-trip,
// key-isolation, default-empty, and stale-name tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/tickets/data/repositories/shared_prefs_ticket_board_column_visibility_repository.dart';
import 'package:aion/features/tickets/domain/entities/ticket_board_column_visibility.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsTicketBoardColumnVisibilityRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'getHiddenColumns returns a default-empty TicketBoardColumnVisibility '
      'when nothing has been saved yet',
      () async {
        final repository = SharedPrefsTicketBoardColumnVisibilityRepository();

        final visibility = await repository.getHiddenColumns('proj-1');

        expect(visibility, const TicketBoardColumnVisibility());
      },
    );

    test(
      'setHiddenColumns then getHiddenColumns round-trips the hidden set',
      () async {
        final repository = SharedPrefsTicketBoardColumnVisibilityRepository();
        const visibility = TicketBoardColumnVisibility(
          hiddenStatuses: {'backlog', 'cancelled'},
        );

        await repository.setHiddenColumns('proj-1', visibility);
        final read = await repository.getHiddenColumns('proj-1');

        expect(read, visibility);
      },
    );

    test(
      'project-id-prefixed keys isolate two different projects from each '
      'other',
      () async {
        final repository = SharedPrefsTicketBoardColumnVisibilityRepository();

        await repository.setHiddenColumns(
          'proj-a',
          const TicketBoardColumnVisibility(
            hiddenStatuses: {'backlog'},
          ),
        );
        await repository.setHiddenColumns(
          'proj-b',
          const TicketBoardColumnVisibility(
            hiddenStatuses: {'done'},
          ),
        );

        final visibilityA = await repository.getHiddenColumns('proj-a');
        final visibilityB = await repository.getHiddenColumns('proj-b');

        expect(visibilityA.hiddenStatuses, {'backlog'});
        expect(visibilityB.hiddenStatuses, {'done'});
      },
    );

    test(
      'setHiddenColumns with an empty selection clears a previously saved '
      'hidden set',
      () async {
        final repository = SharedPrefsTicketBoardColumnVisibilityRepository();
        await repository.setHiddenColumns(
          'proj-1',
          const TicketBoardColumnVisibility(
            hiddenStatuses: {'backlog', 'cancelled'},
          ),
        );

        await repository.setHiddenColumns(
          'proj-1',
          const TicketBoardColumnVisibility(),
        );
        final read = await repository.getHiddenColumns('proj-1');

        expect(read, const TicketBoardColumnVisibility());
      },
    );

    test(
      'a stale stored name (e.g. a status the project has since deleted '
      'or renamed) round-trips unvalidated — this repository performs '
      'no enum-membership filtering, since a status is now project-'
      'defined data rather than a fixed enum',
      () async {
        SharedPreferences.setMockInitialValues({
          'ticket_board_column_visibility.proj-1.hiddenStatuses': [
            'backlog',
            'someRemovedStatus',
          ],
        });
        final repository = SharedPrefsTicketBoardColumnVisibilityRepository();

        final visibility = await repository.getHiddenColumns('proj-1');

        expect(visibility.hiddenStatuses, {'backlog', 'someRemovedStatus'});
      },
    );
  });
}
