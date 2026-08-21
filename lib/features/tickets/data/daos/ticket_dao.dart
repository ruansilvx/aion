// data/daos/ticket_dao.dart — TicketDao Drift accessor (data layer).

import 'dart:collection';

import 'package:drift/drift.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/models/ticket_model.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_direction.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_field.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/utils/ticket_sort_comparator.dart'
    show ticketFieldEnumValues;

part 'ticket_dao.g.dart';

/// Drift accessor for [TicketsTable] and [TicketIdSequenceTable]. Owns the
/// transactional human-readable ID generation logic, plus the trash/
/// soft-delete subtree traversal ([getDescendantIds]/[getAncestorIds]) and
/// bulk write helpers ([softDeleteByIds]/[restoreByIds]/[deleteTicketRows]/
/// [updateStatusByIds]/[updatePriorityByIds]) used by
/// [DriftTicketRepository]'s trash/restore/permanent-delete/bulk-status/
/// bulk-priority methods.
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

  /// Returns the ticket row whose human-readable `ticket_id` column (a
  /// `.unique()` column, so at most one row can ever match) equals
  /// [ticketId], or `null` if none exists. Distinct from [getTicketById],
  /// which looks up the primary-key `id` instead. Added for
  /// `aion-arch/changes/ticket-crud-tool-calls`.
  Future<TicketData?> getTicketByTicketId(String ticketId) {
    return (select(
      ticketsTable,
    )..where((t) => t.ticketId.equals(ticketId))).getSingleOrNull();
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

  /// Inserts [entry] with whatever `ticketId` it already carries,
  /// preserving it verbatim instead of generating one from
  /// [TicketIdSequenceTable] the way [insertTicket] does. Used by
  /// `TicketDbReconstructionService`'s true-import path, where a
  /// `tickets/*.md` file's own `ticketId` has no matching existing row
  /// and must be kept rather than replaced — otherwise the
  /// file/DB naming correspondence the git-projection/sync mechanism
  /// depends on breaks.
  ///
  /// Runs in a single transaction: inserts [entry] as-is, then parses the
  /// substring after the last `-` in its `ticketId` as an `int`; if it
  /// parses and is greater than the current [TicketIdSequenceTable.seq],
  /// advances `seq` to that value so a later [insertTicket] call can
  /// never mint an id that collides with the one just inserted. A
  /// `ticketId` whose suffix doesn't parse as an integer still inserts
  /// successfully — only the sequence bump is skipped for it, since
  /// `TicketsTable.ticketId` has no format constraint beyond uniqueness.
  Future<void> insertTicketPreservingId(TicketsTableCompanion entry) {
    return transaction(() async {
      await into(ticketsTable).insert(entry);

      final ticketId = entry.ticketId.value;
      final dashIndex = ticketId.lastIndexOf('-');
      if (dashIndex == -1) return;
      final suffix = int.tryParse(ticketId.substring(dashIndex + 1));
      if (suffix == null) return;

      final current = await (select(
        ticketIdSequenceTable,
      )..where((t) => t.id.equals(1))).getSingleOrNull();
      if ((current?.seq ?? 0) >= suffix) return;

      await into(ticketIdSequenceTable).insertOnConflictUpdate(
        TicketIdSequenceTableCompanion(id: const Value(1), seq: Value(suffix)),
      );
    });
  }

  /// Adds [minutesDelta] to the `time_spent` column of the ticket row with
  /// primary key [id] — treating a `NULL` `time_spent` as `0` — and bumps
  /// `updated_at` to [updatedAtMs], both in a single atomic `UPDATE`
  /// statement rather than a separate read-then-write round trip. This is
  /// what makes [addTimeSpent] race-free against a concurrent
  /// [updateFields] write to the same row's other columns (e.g. a human
  /// editing the ticket's title in the UI at the same moment a `log_time`
  /// tool call lands) — a read-modify-write through [updateFields] would
  /// silently clobber whichever side lost the race. No-ops if [id] does
  /// not exist (the `WHERE` clause simply matches zero rows). Added for
  /// `aion-arch/changes/ticket-crud-tool-calls`.
  Future<void> addTimeSpent(String id, int minutesDelta, int updatedAtMs) {
    return customUpdate(
      'UPDATE tickets SET time_spent = COALESCE(time_spent, 0) + ?, '
      'updated_at = ? WHERE id = ?',
      variables: [
        Variable<int>(minutesDelta),
        Variable<int>(updatedAtMs),
        Variable<String>(id),
      ],
      updates: {ticketsTable},
    );
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

  /// Sets `status` (as its `.name`) and bumps `updated_at` to [updatedAtMs]
  /// for every id in [ids]. Bulk `UPDATE ... WHERE id IN (...)`, same
  /// shape as [softDeleteByIds]/[restoreByIds] — used by bulk status
  /// change.
  Future<void> updateStatusByIds(
    List<String> ids,
    String status,
    int updatedAtMs,
  ) {
    return (update(ticketsTable)..where((t) => t.id.isIn(ids))).write(
      TicketsTableCompanion(
        status: Value(status),
        updatedAt: Value(updatedAtMs),
      ),
    );
  }

  /// Sets `priority` (as its `.name`) and bumps `updated_at` to
  /// [updatedAtMs] for every id in [ids]. Bulk `UPDATE ... WHERE id IN
  /// (...)`, same shape as [updateStatusByIds] — used by bulk priority
  /// edit.
  Future<void> updatePriorityByIds(
    List<String> ids,
    TicketPriority priority,
    int updatedAtMs,
  ) {
    return (update(ticketsTable)..where((t) => t.id.isIn(ids))).write(
      TicketsTableCompanion(
        priority: Value(priority.name),
        updatedAt: Value(updatedAtMs),
      ),
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

  /// Returns one page of tickets matching every filter, excluding trashed
  /// tickets. Within a field, values in [statuses]/[types]/[priorities]
  /// combine as OR; an empty set for a field means no constraint on it —
  /// the three fields combine with each other, and with [query], as AND.
  ///
  /// Ordered per [sort] (see [_sortSql]/[_orderingModeFor]). With [query]
  /// null/empty, builds a query-builder `OrderingTerm` for [sort.field]
  /// (identical row shape to [getAllTickets] when every filter set is
  /// also empty and [sort] is `createdAt` descending), plus an always-on
  /// `created_at DESC` tiebreaker so same-value rows (e.g. two `critical`
  /// tickets) stay stably ordered newest-first — omitted when [sort.field]
  /// is itself `createdAt` (would be redundant).
  /// [TicketSortField.relevance] in this branch — only reachable when an
  /// earlier explicit `relevance` selection survives a query being
  /// cleared, since `relevance` has no score to order by with no query
  /// active — falls back to the same `created_at` descending ordering
  /// this method used before sort existed. With [query] set, matches
  /// against the `tickets_fts` index (title + description); the `ORDER
  /// BY` is `bm25(tickets_fts) ASC` (SQLite's bm25 scores are negative,
  /// more-negative meaning a better match) only when [sort.field] is
  /// [TicketSortField.relevance] — every other field instead orders by
  /// [sort] (case-or-column SQL + `created_at DESC` tiebreaker, same rule
  /// as the no-query branch), so e.g. "search for `bug` sorted by
  /// priority" returns matching rows in priority order, not relevance
  /// order. Both branches apply [limit]/[offset] mechanically — this
  /// method makes no `hasMore` decision of its own; that's the caller's
  /// responsibility (see [DriftTicketRepository.searchTickets]).
  Future<List<TicketData>> searchTickets({
    String? query,
    Set<String> statuses = const {},
    Set<TicketType> types = const {},
    Set<TicketPriority> priorities = const {},
    required TicketListSort sort,
    required int limit,
    int offset = 0,
    List<String> statusSortOrder = const [],
  }) {
    final trimmed = query?.trim() ?? '';
    if (trimmed.isEmpty) {
      // `relevance` has no score to order by with no query active — see
      // this method's dartdoc.
      final effectiveSort = sort.field == TicketSortField.relevance
          ? const TicketListSort(
              field: TicketSortField.createdAt,
              direction: TicketSortDirection.descending,
            )
          : sort;
      final q = select(ticketsTable)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([
          (t) => OrderingTerm(
            expression: CustomExpression<int>(
              _sortSql(effectiveSort.field, statusSortOrder),
            ),
            mode: _orderingModeFor(effectiveSort.direction),
          ),
          if (effectiveSort.field != TicketSortField.createdAt)
            (t) => OrderingTerm.desc(t.createdAt),
        ])
        ..limit(limit, offset: offset);
      if (statuses.isNotEmpty) {
        q.where((t) => t.status.isIn(statuses));
      }
      if (types.isNotEmpty) {
        q.where((t) => t.type.isIn(types.map((v) => v.name)));
      }
      if (priorities.isNotEmpty) {
        q.where((t) => t.priority.isIn(priorities.map((v) => v.name)));
      }
      return q.get();
    }

    final conditions = <String>[
      'tickets_fts MATCH ?',
      'tickets.deleted_at IS NULL',
    ];
    final variables = <Variable<Object>>[Variable(_buildFtsQuery(trimmed))];
    void addInClause(String column, Set<String> names) {
      if (names.isEmpty) return;
      final placeholders = List.filled(names.length, '?').join(', ');
      conditions.add('$column IN ($placeholders)');
      for (final name in names) {
        variables.add(Variable(name));
      }
    }

    addInClause('tickets.status', statuses);
    addInClause('tickets.type', types.map((v) => v.name).toSet());
    addInClause('tickets.priority', priorities.map((v) => v.name).toSet());
    variables.add(Variable(limit));
    variables.add(Variable(offset));

    final orderBySql = sort.field == TicketSortField.relevance
        ? 'bm25(tickets_fts) ASC'
        : '${_sortSql(sort.field, statusSortOrder)} '
              '${sort.direction == TicketSortDirection.ascending ? 'ASC' : 'DESC'}'
              '${sort.field == TicketSortField.createdAt ? '' : ', tickets.created_at DESC'}';

    return customSelect(
      'SELECT tickets.* FROM tickets_fts '
      'JOIN tickets ON tickets.rowid = tickets_fts.rowid '
      'WHERE ${conditions.join(' AND ')} '
      'ORDER BY $orderBySql '
      'LIMIT ? OFFSET ?',
      variables: variables,
      readsFrom: {ticketsTable},
    ).map((row) => ticketsTable.map(row.data)).get();
  }

  /// Maps [field]'s declared enum values to their ordinal position, as a
  /// SQL `CASE` expression over that field's column (SQLite has no
  /// notion of Dart enum declaration order, so this expresses it
  /// explicitly) — for [TicketSortField.priority]/[TicketSortField.type]
  /// only. Indexes into the shared [ticketFieldEnumValues] lookup
  /// (`ticket_sort_comparator.dart`) so this SQL-string builder and the
  /// in-memory `ticketSortComparator` can't silently disagree on ordinal
  /// position. Returns `null` for every other field — see
  /// [_statusOrdinalCaseSql]/[_directColumnSql].
  String? _enumOrdinalCaseSql(TicketSortField field) {
    final values = ticketFieldEnumValues[field];
    if (values == null) return null;
    final column = switch (field) {
      TicketSortField.priority => 'tickets.priority',
      TicketSortField.type => 'tickets.type',
      TicketSortField.status ||
      TicketSortField.createdAt ||
      TicketSortField.updatedAt ||
      TicketSortField.relevance => throw StateError(
        'unreachable — ticketFieldEnumValues has no entry for $field',
      ),
    };
    final whens = [
      for (var i = 0; i < values.length; i++)
        'WHEN \'${values[i].name}\' THEN $i',
    ].join(' ');
    return 'CASE $column $whens ELSE ${values.length} END';
  }

  /// Builds [TicketSortField.status]'s SQL `CASE` expression from
  /// [statusSortOrder] — the caller's currently-configured `WorkflowStatus`
  /// name list, already sorted by `WorkflowStatus.sortOrder` — since a
  /// status is now project-configured data, not a fixed enum. A status
  /// name absent from [statusSortOrder] (e.g. deleted since a ticket was
  /// last written) sorts after every recognized status, mirroring
  /// [_enumOrdinalCaseSql]'s `ELSE` clause. An empty [statusSortOrder]
  /// (no caller-supplied order — e.g. a direct `TicketDao` test that
  /// doesn't care about status ordering) has no `WHEN` clause to offer
  /// SQL's `CASE` syntax, which requires at least one; falls back to a
  /// constant `0` expression instead of building invalid SQL, so every
  /// row simply ties on this field (equivalent to not sorting by status
  /// at all).
  String _statusOrdinalCaseSql(List<String> statusSortOrder) {
    // An arithmetic expression, not a bare `0` (parenthesizing alone
    // doesn't help — SQLite still resolves `(0)` back to the integer
    // literal `0`) — SQLite's ORDER BY grammar treats a bare integer
    // literal as a 1-based column-position reference (and `0` is out of
    // range), not a constant expression. `0 + 0` can't be mistaken for
    // a column-position literal.
    if (statusSortOrder.isEmpty) return '0 + 0';
    final whens = [
      for (var i = 0; i < statusSortOrder.length; i++)
        'WHEN \'${statusSortOrder[i]}\' THEN $i',
    ].join(' ');
    return 'CASE tickets.status $whens ELSE ${statusSortOrder.length} END';
  }

  /// The literal column [field] sorts by directly —
  /// [TicketSortField.createdAt]/[TicketSortField.updatedAt] only. `null`
  /// for priority/status/type (see [_enumOrdinalCaseSql]/
  /// [_statusOrdinalCaseSql]) and relevance (handled via `bm25()` directly
  /// in [searchTickets], never via this column-SQL path).
  String? _directColumnSql(TicketSortField field) => switch (field) {
    TicketSortField.createdAt => 'tickets.created_at',
    TicketSortField.updatedAt => 'tickets.updated_at',
    _ => null,
  };

  /// The case-or-column SQL fragment [field] sorts by —
  /// [_statusOrdinalCaseSql] for status, [_enumOrdinalCaseSql] for
  /// priority/type, [_directColumnSql] for createdAt/updatedAt. Never
  /// called with [TicketSortField.relevance] — both of [searchTickets]'s
  /// branches resolve that case themselves before reaching this helper
  /// (the no-query branch substitutes an `effectiveSort` of `createdAt`
  /// descending; the FTS branch keeps its own `bm25()` clause instead of
  /// calling this at all).
  String _sortSql(TicketSortField field, List<String> statusSortOrder) {
    if (field == TicketSortField.status) {
      return _statusOrdinalCaseSql(statusSortOrder);
    }
    return _enumOrdinalCaseSql(field) ??
        _directColumnSql(field) ??
        (throw StateError('_sortSql must not be called with relevance'));
  }

  /// Converts [direction] to Drift's [OrderingMode].
  OrderingMode _orderingModeFor(TicketSortDirection direction) =>
      direction == TicketSortDirection.ascending
      ? OrderingMode.asc
      : OrderingMode.desc;

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
