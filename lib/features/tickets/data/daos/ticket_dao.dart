// data/daos/ticket_dao.dart — TicketDao Drift accessor (data layer).

import 'package:drift/drift.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/data/models/ticket_model.dart';

part 'ticket_dao.g.dart';

/// Drift accessor for [TicketsTable] and [TicketIdSequenceTable]. Owns the
/// transactional human-readable ID generation logic.
@DriftAccessor(tables: [TicketsTable, TicketIdSequenceTable])
class TicketDao extends DatabaseAccessor<AppDatabase> with _$TicketDaoMixin {
  /// Creates a [TicketDao] bound to [db].
  TicketDao(super.db);

  /// Returns all tickets, most recently created first.
  Future<List<TicketData>> getAllTickets() {
    return (select(ticketsTable)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Returns the ticket row with primary key [id], or `null` if none exists.
  Future<TicketData?> getTicketById(String id) {
    return (select(ticketsTable)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Inserts [entry] with a freshly generated human-readable ticket ID.
  ///
  /// Runs in a single transaction: reads the current sequence value,
  /// increments it, writes it back, builds `'$prefix-$newSeq'`, and inserts
  /// the ticket with that ID. Deterministic and race-free under SQLite's
  /// single-writer model.
  ///
  /// Returns the generated ticket ID (e.g. `"AIO-3"`).
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
