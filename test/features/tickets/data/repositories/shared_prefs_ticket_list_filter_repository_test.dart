// test/features/tickets/data/repositories/shared_prefs_ticket_list_filter_repository_test.dart
// — SharedPrefsTicketListFilterRepository round-trip, key-isolation, and
// default-empty tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/tickets/data/repositories/shared_prefs_ticket_list_filter_repository.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_filters.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsTicketListFilterRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'getFilters returns a default-empty TicketListFilters when nothing '
      'has been saved yet',
      () async {
        final repository = SharedPrefsTicketListFilterRepository();

        final filters = await repository.getFilters('proj-1');

        expect(filters, const TicketListFilters());
      },
    );

    test('setFilters then getFilters round-trips all three fields', () async {
      final repository = SharedPrefsTicketListFilterRepository();
      const filters = TicketListFilters(
        statuses: {'todo', 'inProgress'},
        types: {TicketType.bug},
        priorities: {TicketPriority.high, TicketPriority.critical},
      );

      await repository.setFilters('proj-1', filters);
      final read = await repository.getFilters('proj-1');

      expect(read, filters);
    });

    test(
      'project-id-prefixed keys isolate two different projects from each '
      'other',
      () async {
        final repository = SharedPrefsTicketListFilterRepository();

        await repository.setFilters(
          'proj-a',
          const TicketListFilters(statuses: {'todo'}),
        );
        await repository.setFilters(
          'proj-b',
          const TicketListFilters(statuses: {'done'}),
        );

        final filtersA = await repository.getFilters('proj-a');
        final filtersB = await repository.getFilters('proj-b');

        expect(filtersA.statuses, {'todo'});
        expect(filtersB.statuses, {'done'});
      },
    );

    test(
      'setFilters with an empty TicketListFilters clears a previously '
      'saved selection',
      () async {
        final repository = SharedPrefsTicketListFilterRepository();
        await repository.setFilters(
          'proj-1',
          const TicketListFilters(
            statuses: {'todo'},
            types: {TicketType.bug},
            priorities: {TicketPriority.high},
          ),
        );

        await repository.setFilters('proj-1', const TicketListFilters());
        final read = await repository.getFilters('proj-1');

        expect(read, const TicketListFilters());
      },
    );
  });
}
