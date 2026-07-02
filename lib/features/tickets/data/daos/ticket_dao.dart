import 'package:drift/drift.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/data/models/ticket_model.dart';

part 'ticket_dao.g.dart';

@DriftAccessor(tables: [TicketsTable, TicketIdSequenceTable])
class TicketDao extends DatabaseAccessor<AppDatabase> with _$TicketDaoMixin {
  TicketDao(super.db);

  Future<List<TicketData>> getAllTickets() {
    return (select(ticketsTable)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<TicketData?> getTicketById(String id) {
    return (select(ticketsTable)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<String> insertTicket(
    TicketsTableCompanion entry,
    String prefix,
  ) {
    return transaction<String>(() async {
      final current = await (select(ticketIdSequenceTable)
            ..where((t) => t.id.equals(1)))
          .getSingleOrNull();
      final newSeq = (current?.seq ?? 0) + 1;

      await into(ticketIdSequenceTable).insertOnConflictUpdate(
        TicketIdSequenceTableCompanion(
          id: const Value(1),
          seq: Value(newSeq),
        ),
      );

      final ticketId = '$prefix-$newSeq';
      await into(ticketsTable).insert(entry.copyWith(ticketId: Value(ticketId)));

      return ticketId;
    });
  }
}
