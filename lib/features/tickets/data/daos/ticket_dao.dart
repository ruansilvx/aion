// data/daos/ticket_dao.dart — TicketDao Drift accessor (data layer).

import 'dart:collection';

import 'package:drift/drift.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/models/ticket_model.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

part 'ticket_dao.g.dart';

/// Drift accessor for [TicketsTable] and [TicketIdSequenceTable]. Owns the
/// transactional human-readable ID generation logic, plus the trash/
/// soft-delete subtree traversal ([getDescendantIds]/[getAncestorIds]) and
/// bulk write helpers ([softDeleteByIds]/[restoreByIds]/[deleteTicketRows])
/// used by [DriftTicketRepository]'s trash/restore/permanent-delete methods.
@DriftAccessor(tables: [TicketsTable, TicketIdSequenceTable])
class TicketDao extends DatabaseAccessor<AppDatabase> with _$TicketDaoMixin {
  /// Creates a [TicketDao] bound to [db].
  TicketDao(super.db);

  /// Returns all live (non-trashed) tickets, most recently created first.
  Future<List<TicketData>> getAllTickets() {
    return (select(ticketsTable)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
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

  /// Returns the ids of every ticket in [rootId]'s structural subtree
  /// (children, grandchildren, ...), not including [rootId] itself.
  /// Breadth-first, with a visited-set guard against a cycle (shouldn't
  /// be possible — [TicketsCubit.updateTicketParent] rejects cycles at
  /// write time — but cheap insurance against an infinite loop if one
  /// ever existed).
  Future<List<String>> getDescendantIds(String rootId) async {
    final result = <String>[];
    final visited = <String>{rootId};
    final queue = Queue<String>()..add(rootId);
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final children = await (select(
        ticketsTable,
      )..where((t) => t.parentId.equals(current))).get();
      for (final child in children) {
        if (visited.add(child.id)) {
          result.add(child.id);
          queue.add(child.id);
        }
      }
    }
    return result;
  }

  /// Returns the ids of every ticket above [id] in its structural parent
  /// chain (its parent, its parent's parent, ...), not including [id]
  /// itself. Stops at the first ticket with no parent, or defensively at
  /// a repeated id (cycle guard, same rationale as [getDescendantIds]).
  Future<List<String>> getAncestorIds(String id) async {
    final result = <String>[];
    final visited = <String>{id};
    var currentId = id;
    while (true) {
      final row = await getTicketById(currentId);
      final parentId = row?.parentId;
      if (parentId == null || !visited.add(parentId)) break;
      result.add(parentId);
      currentId = parentId;
    }
    return result;
  }

  /// Sets `deleted_at = deletedAtMs` for every id in [ids]. Bulk
  /// `UPDATE ... WHERE id IN (...)` — used by trash operations.
  Future<void> softDeleteByIds(List<String> ids, int deletedAtMs) {
    return (update(ticketsTable)..where((t) => t.id.isIn(ids))).write(
      TicketsTableCompanion(deletedAt: Value(deletedAtMs)),
    );
  }

  /// Sets `deleted_at = NULL` for every id in [ids]. Bulk
  /// `UPDATE ... WHERE id IN (...)` — used by restore. A no-op per row
  /// already live (idempotent), so callers don't need to filter down to
  /// "currently trashed" ids first.
  Future<void> restoreByIds(List<String> ids) {
    return (update(ticketsTable)..where((t) => t.id.isIn(ids))).write(
      const TicketsTableCompanion(deletedAt: Value(null)),
    );
  }

  /// Deletes every ticket row with a primary key in [ids]. Callers are
  /// responsible for cascading to dependent rows (comments, links) first.
  Future<void> deleteTicketRows(List<String> ids) {
    return (delete(ticketsTable)..where((t) => t.id.isIn(ids))).go();
  }

  /// Returns every trashed ticket row (`deleted_at IS NOT NULL`), most
  /// recently trashed first.
  Future<List<TicketData>> getTrashedTickets() {
    return (select(ticketsTable)
          ..where((t) => t.deletedAt.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)]))
        .get();
  }

  /// Returns one page of tickets matching every non-null filter (ANDed),
  /// excluding trashed tickets. With [query] null/empty, returns a plain
  /// filtered list ordered by `created_at desc` (identical shape to
  /// [getAllTickets] when every filter is also null). With [query] set,
  /// matches against the `tickets_fts` index (title + description) and
  /// orders by relevance (`bm25`, ascending — SQLite's bm25 scores are
  /// negative, more-negative meaning a better match). Both branches apply
  /// [limit]/[offset] mechanically — this method makes no `hasMore`
  /// decision of its own; that's the caller's responsibility (see
  /// [DriftTicketRepository.searchTickets]).
  Future<List<TicketData>> searchTickets({
    String? query,
    TicketStatus? status,
    TicketType? type,
    TicketPriority? priority,
    required int limit,
    int offset = 0,
  }) {
    final trimmed = query?.trim() ?? '';
    if (trimmed.isEmpty) {
      final q = select(ticketsTable)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(limit, offset: offset);
      if (status != null) q.where((t) => t.status.equals(status.name));
      if (type != null) q.where((t) => t.type.equals(type.name));
      if (priority != null) q.where((t) => t.priority.equals(priority.name));
      return q.get();
    }

    final conditions = <String>[
      'tickets_fts MATCH ?',
      'tickets.deleted_at IS NULL',
    ];
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
    variables.add(Variable(limit));
    variables.add(Variable(offset));

    return customSelect(
      'SELECT tickets.* FROM tickets_fts '
      'JOIN tickets ON tickets.rowid = tickets_fts.rowid '
      'WHERE ${conditions.join(' AND ')} '
      'ORDER BY bm25(tickets_fts) ASC '
      'LIMIT ? OFFSET ?',
      variables: variables,
      readsFrom: {ticketsTable},
    ).map((row) => ticketsTable.map(row.data)).get();
  }

  /// Returns every live (non-trashed) ticket row whose `parent_id` equals
  /// [parentId] (or, when [parentId] is `null`, every live row with a
  /// `NULL` `parent_id`) and whose `type` is one of [types]. Used by the
  /// Documentation section to load one tree level (root docs, or one
  /// page's direct children) at a time.
  Future<List<TicketData>> getTicketsByParent(
    String? parentId, {
    required List<TicketType> types,
  }) {
    final typeNames = types.map((t) => t.name).toList();
    final q = select(ticketsTable)
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.type.isIn(typeNames))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    if (parentId == null) {
      q.where((t) => t.parentId.isNull());
    } else {
      q.where((t) => t.parentId.equals(parentId));
    }
    return q.get();
  }

  /// Returns every live (non-trashed) ticket row whose `type` is one of
  /// [types], regardless of `parent_id` or nesting depth. Used by
  /// [TicketDocumentSearchService] to scan every page/resource ticket.
  Future<List<TicketData>> getAllTicketsByType(List<TicketType> types) {
    final typeNames = types.map((t) => t.name).toList();
    return (select(ticketsTable)
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.type.isIn(typeNames))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
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
