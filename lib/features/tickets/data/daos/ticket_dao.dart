// data/daos/ticket_dao.dart — TicketDao Drift accessor (data layer).

import 'package:drift/drift.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/models/ticket_model.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

part 'ticket_dao.g.dart';

/// Drift accessor for [TicketsTable] and [TicketIdSequenceTable]. Owns the
/// transactional human-readable ID generation logic.
@DriftAccessor(tables: [TicketsTable, TicketIdSequenceTable])
class TicketDao extends DatabaseAccessor<AppDatabase> with _$TicketDaoMixin {
  /// Creates a [TicketDao] bound to [db].
  TicketDao(super.db);

  /// Returns all tickets, most recently created first.
  Future<List<TicketData>> getAllTickets() {
    return (select(
      ticketsTable,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
  }

  /// Returns the ticket row with primary key [id], or `null` if none exists.
  Future<TicketData?> getTicketById(String id) {
    return (select(
      ticketsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Inserts [entry] with a freshly generated human-readable ticket ID.
  ///
  /// Runs in a single transaction: reads the current sequence value,
  /// increments it, writes it back, builds `'$prefix-$newSeq'`, and inserts
  /// the ticket with that ID. Deterministic and race-free under SQLite's
  /// single-writer model.
  ///
  /// Returns the generated ticket ID (e.g. `"AIO-3"`).
  Future<String> insertTicket(TicketsTableCompanion entry, String prefix) {
    return transaction<String>(() async {
      final current = await (select(
        ticketIdSequenceTable,
      )..where((t) => t.id.equals(1))).getSingleOrNull();
      final newSeq = (current?.seq ?? 0) + 1;

      await into(ticketIdSequenceTable).insertOnConflictUpdate(
        TicketIdSequenceTableCompanion(id: const Value(1), seq: Value(newSeq)),
      );

      final ticketId = '$prefix-$newSeq';
      await into(
        ticketsTable,
      ).insert(entry.copyWith(ticketId: Value(ticketId)));

      return ticketId;
    });
  }

  /// Applies [companion] to the ticket row with primary key [id]. Generic —
  /// [companion] may cover any subset of columns; both status-only updates
  /// ([DriftTicketRepository.updateTicketStatus]) and general field updates
  /// ([DriftTicketRepository.updateTicket]) go through this one method.
  Future<void> updateFields(String id, TicketsTableCompanion companion) {
    return (update(
      ticketsTable,
    )..where((t) => t.id.equals(id))).write(companion);
  }

  /// Returns how many tickets have `parent_id == parentId`. Used by
  /// [DriftTicketRepository.deleteTicket] to block deletion of tickets
  /// with structural children.
  Future<int> countChildTickets(String parentId) {
    final query = selectOnly(ticketsTable)
      ..addColumns([ticketsTable.id.count()])
      ..where(ticketsTable.parentId.equals(parentId));
    return query
        .map((row) => row.read(ticketsTable.id.count()) ?? 0)
        .getSingle();
  }

  /// Deletes the ticket row with primary key [id]. Callers are responsible
  /// for cascading to dependent rows (comments, links) first.
  Future<void> deleteTicketRow(String id) {
    return (delete(ticketsTable)..where((t) => t.id.equals(id))).go();
  }

  /// Returns tickets matching every non-null filter (ANDed). With [query]
  /// null/empty, returns a plain filtered list ordered by `created_at desc`
  /// (identical shape to [getAllTickets] when every filter is also null).
  /// With [query] set, matches against the `tickets_fts` index (title +
  /// description) and orders by relevance (`bm25`, ascending — SQLite's
  /// bm25 scores are negative, more-negative meaning a better match).
  Future<List<TicketData>> searchTickets({
    String? query,
    TicketStatus? status,
    TicketType? type,
    TicketPriority? priority,
  }) {
    final trimmed = query?.trim() ?? '';
    if (trimmed.isEmpty) {
      final q = select(ticketsTable)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
      if (status != null) q.where((t) => t.status.equals(status.name));
      if (type != null) q.where((t) => t.type.equals(type.name));
      if (priority != null) q.where((t) => t.priority.equals(priority.name));
      return q.get();
    }

    final conditions = <String>['tickets_fts MATCH ?'];
    final variables = <Variable<Object>>[Variable(_buildFtsQuery(trimmed))];
    if (status != null) {
      conditions.add('tickets.status = ?');
      variables.add(Variable(status.name));
    }
    if (type != null) {
      conditions.add('tickets.type = ?');
      variables.add(Variable(type.name));
    }
    if (priority != null) {
      conditions.add('tickets.priority = ?');
      variables.add(Variable(priority.name));
    }

    return customSelect(
      'SELECT tickets.* FROM tickets_fts '
      'JOIN tickets ON tickets.rowid = tickets_fts.rowid '
      'WHERE ${conditions.join(' AND ')} '
      'ORDER BY bm25(tickets_fts) ASC',
      variables: variables,
      readsFrom: {ticketsTable},
    ).map((row) => ticketsTable.map(row.data)).get();
  }

  /// Converts free-typed search text into a safe FTS5 MATCH query: each
  /// whitespace-separated token becomes a quoted, prefix-matched literal
  /// (`"token"*`), ANDed together (FTS5's default when terms are just
  /// space-separated). Quoting every token avoids FTS5 query-syntax errors
  /// from characters that are otherwise special to FTS5 (`-`, `(`, `"`,
  /// `:`, ...) appearing in ordinary user input; an embedded `"` is escaped
  /// by doubling it, per FTS5's string-literal rules.
  String _buildFtsQuery(String raw) {
    final tokens = raw.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    return tokens.map((t) => '"${t.replaceAll('"', '""')}"*').join(' ');
  }
}
