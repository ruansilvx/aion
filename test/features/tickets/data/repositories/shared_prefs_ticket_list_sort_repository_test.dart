// test/features/tickets/data/repositories/shared_prefs_ticket_list_sort_repository_test.dart
// — SharedPrefsTicketListSortRepository round-trip, key-isolation, and
// default-null tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/tickets/data/repositories/shared_prefs_ticket_list_sort_repository.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_direction.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_field.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsTicketListSortRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('getSort returns null when nothing has been saved yet', () async {
      final repository = SharedPrefsTicketListSortRepository();

      final sort = await repository.getSort('proj-1');

      expect(sort, isNull);
    });

    test('setSort then getSort round-trips field and direction', () async {
      final repository = SharedPrefsTicketListSortRepository();
      const sort = TicketListSort(
        field: TicketSortField.priority,
        direction: TicketSortDirection.ascending,
      );

      await repository.setSort('proj-1', sort);
      final read = await repository.getSort('proj-1');

      expect(read, sort);
    });

    test('project-id-prefixed keys isolate two different projects from each '
        'other', () async {
      final repository = SharedPrefsTicketListSortRepository();

      await repository.setSort(
        'proj-a',
        const TicketListSort(
          field: TicketSortField.status,
          direction: TicketSortDirection.ascending,
        ),
      );
      await repository.setSort(
        'proj-b',
        const TicketListSort(
          field: TicketSortField.updatedAt,
          direction: TicketSortDirection.descending,
        ),
      );

      final sortA = await repository.getSort('proj-a');
      final sortB = await repository.getSort('proj-b');

      expect(
        sortA,
        const TicketListSort(
          field: TicketSortField.status,
          direction: TicketSortDirection.ascending,
        ),
      );
      expect(
        sortB,
        const TicketListSort(
          field: TicketSortField.updatedAt,
          direction: TicketSortDirection.descending,
        ),
      );
    });

    test('setSort overwrites a previously saved selection for the same '
        'project', () async {
      final repository = SharedPrefsTicketListSortRepository();
      await repository.setSort(
        'proj-1',
        const TicketListSort(
          field: TicketSortField.priority,
          direction: TicketSortDirection.ascending,
        ),
      );

      await repository.setSort(
        'proj-1',
        const TicketListSort(
          field: TicketSortField.createdAt,
          direction: TicketSortDirection.descending,
        ),
      );
      final read = await repository.getSort('proj-1');

      expect(
        read,
        const TicketListSort(
          field: TicketSortField.createdAt,
          direction: TicketSortDirection.descending,
        ),
      );
    });
  });
}
