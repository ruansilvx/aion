// data/repositories/drift_ticket_repository.dart — Drift implementation of TicketRepository (data layer).

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/ticket_search_page.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';

/// Drift-backed implementation of [TicketRepository]. Maps between the
/// generated `TicketData` row and the [Ticket] domain entity, and resolves
/// the configured ticket-ID prefix from [SharedPreferences].
class DriftTicketRepository implements TicketRepository {
  /// Creates a [DriftTicketRepository] backed by [_db].
  DriftTicketRepository(this._db);

  final AppDatabase _db;

  /// SharedPreferences key for the configured ticket-ID prefix.
  static const _prefixKey = 'ticket_id_prefix';

  /// Prefix used when no `ticket_id_prefix` preference is set.
  static const _defaultPrefix = 'AIO';

  @override
  Future<List<Ticket>> getAllTickets() async {
    final rows = await _db.ticketDao.getAllTickets();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<Ticket?> getTicketById(String id) async {
    final row = await _db.ticketDao.getTicketById(id);
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<void> createTicket(Ticket ticket) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = prefs.getString(_prefixKey) ?? _defaultPrefix;

    final companion = TicketsTableCompanion.insert(
      id: ticket.id,
      ticketId: '',
      type: ticket.type.name,
      title: ticket.title,
      description: Value(ticket.description),
      status: ticket.status.name,
      priority: Value(ticket.priority.name),
      parentId: Value(ticket.parentId),
      embedding: Value(ticket.embedding),
      estimate: Value(ticket.estimate),
      timeSpent: Value(ticket.timeSpent),
      createdAt: ticket.createdAt.millisecondsSinceEpoch,
      updatedAt: ticket.updatedAt.millisecondsSinceEpoch,
    );

    await _db.ticketDao.insertTicket(companion, prefix);
  }

  @override
  Future<void> updateTicketStatus(String id, TicketStatus status) {
    return _db.ticketDao.updateFields(
      id,
      TicketsTableCompanion(
        status: Value(status.name),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Writes only `parent_id` and `updated_at` — no validation performed.
  @override
  Future<void> updateTicketParent(String id, String? parentId) {
    return _db.ticketDao.updateFields(
      id,
      TicketsTableCompanion(
        parentId: Value(parentId),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  @override
  Future<void> updateTicket(Ticket ticket) {
    return _db.ticketDao.updateFields(
      ticket.id,
      TicketsTableCompanion(
        title: Value(ticket.title),
        description: Value(ticket.description),
        priority: Value(ticket.priority.name),
        type: Value(ticket.type.name),
        estimate: Value(ticket.estimate),
        timeSpent: Value(ticket.timeSpent),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Requests `[limit] + 1` rows from [TicketDao.searchTickets] to derive
  /// [TicketSearchPage.hasMore] without a separate `COUNT` query: if the
  /// DAO returns more than [limit] rows, another page exists — the extra
  /// row is trimmed before mapping to entities.
  @override
  Future<TicketSearchPage> searchTickets({
    String? query,
    TicketStatus? status,
    TicketType? type,
    TicketPriority? priority,
    required int limit,
    int offset = 0,
  }) async {
    final rows = await _db.ticketDao.searchTickets(
      query: query,
      status: status,
      type: type,
      priority: priority,
      limit: limit + 1,
      offset: offset,
    );
    final hasMore = rows.length > limit;
    final page = hasMore ? rows.take(limit).toList() : rows;
    return TicketSearchPage(
      tickets: page.map(_toEntity).toList(),
      hasMore: hasMore,
    );
  }

  @override
  Future<void> trashTicket(String id) async {
    final existing = await _db.ticketDao.getTicketById(id);
    if (existing == null) {
      throw StateError('Ticket $id does not exist');
    }
    await trashTickets([id]);
  }

  @override
  Future<int> trashTickets(List<String> ids) async {
    final affected = await _resolveTrashCascade(ids);
    if (affected.isEmpty) return 0;
    await _db.ticketDao.softDeleteByIds(
      affected.toList(),
      DateTime.now().millisecondsSinceEpoch,
    );
    return affected.length;
  }

  @override
  Future<int> previewTrashCount(List<String> ids) async {
    return (await _resolveTrashCascade(ids)).length;
  }

  /// Resolves the full set of ticket ids that trashing [ids] would touch:
  /// every id in [ids] that actually exists, plus each one's full
  /// structural descendant subtree (via [TicketDao.getDescendantIds],
  /// which is not filtered by trash status). Shared by [trashTickets]
  /// (which applies it) and [previewTrashCount] (which only reports its
  /// size), so the cascade preview shown before a trash action always
  /// matches exactly what the action itself will touch — including
  /// descendants that are already trashed.
  Future<Set<String>> _resolveTrashCascade(List<String> ids) async {
    final existingIds = <String>[];
    for (final id in ids) {
      if (await _db.ticketDao.getTicketById(id) != null) {
        existingIds.add(id);
      }
    }

    final affected = <String>{...existingIds};
    for (final id in existingIds) {
      affected.addAll(await _db.ticketDao.getDescendantIds(id));
    }
    return affected;
  }

  @override
  Future<void> restoreTicket(String id) async {
    final existing = await _db.ticketDao.getTicketById(id);
    if (existing == null) {
      throw StateError('Ticket $id does not exist');
    }

    final toRestore = <String>{id};
    toRestore.addAll(await _db.ticketDao.getAncestorIds(id));
    toRestore.addAll(await _db.ticketDao.getDescendantIds(id));
    await _db.ticketDao.restoreByIds(toRestore.toList());
  }

  @override
  Future<void> permanentlyDeleteTicket(String id) async {
    final existing = await _db.ticketDao.getTicketById(id);
    if (existing == null) {
      throw StateError('Ticket $id does not exist');
    }

    final ids = <String>{id, ...await _db.ticketDao.getDescendantIds(id)}
        .toList();
    await _db.transaction(() async {
      await _db.commentDao.deleteCommentsForTickets(ids);
      await _db.ticketLinkDao.deleteLinksForTickets(ids);
      await _db.ticketDao.deleteTicketRows(ids);
    });
  }

  @override
  Future<void> emptyTrash() async {
    final trashed = await _db.ticketDao.getTrashedTickets();
    if (trashed.isEmpty) return;
    final ids = trashed.map((t) => t.id).toList();
    await _db.transaction(() async {
      await _db.commentDao.deleteCommentsForTickets(ids);
      await _db.ticketLinkDao.deleteLinksForTickets(ids);
      await _db.ticketDao.deleteTicketRows(ids);
    });
  }

  /// Filters [getTrashedTickets]'s rows by [age] and hard-deletes the
  /// matches, same cascade shape as [emptyTrash]. `row.deletedAt!` is
  /// safe to force-unwrap here: the underlying query is `WHERE
  /// deleted_at IS NOT NULL`, so every row already has a non-null
  /// `deletedAt`.
  @override
  Future<int> purgeTrashOlderThan(Duration age) async {
    final cutoffMs = DateTime.now().subtract(age).millisecondsSinceEpoch;
    final trashed = await _db.ticketDao.getTrashedTickets();
    final ids = trashed
        .where((row) => row.deletedAt! < cutoffMs)
        .map((row) => row.id)
        .toList();
    if (ids.isEmpty) return 0;

    await _db.transaction(() async {
      await _db.commentDao.deleteCommentsForTickets(ids);
      await _db.ticketLinkDao.deleteLinksForTickets(ids);
      await _db.ticketDao.deleteTicketRows(ids);
    });
    return ids.length;
  }

  @override
  Future<List<Ticket>> getTrashedTickets() async {
    final rows = await _db.ticketDao.getTrashedTickets();
    return rows.map(_toEntity).toList();
  }

  /// Maps a generated [TicketData] row to the [Ticket] domain entity,
  /// falling back to safe defaults for unrecognised enum strings.
  Ticket _toEntity(TicketData row) {
    return Ticket(
      id: row.id,
      ticketId: row.ticketId,
      type: TicketType.values.firstWhere(
        (e) => e.name == row.type,
        orElse: () => TicketType.task,
      ),
      title: row.title,
      description: row.description,
      status: TicketStatus.values.firstWhere(
        (e) => e.name == row.status,
        orElse: () => TicketStatus.backlog,
      ),
      priority: TicketPriority.values.firstWhere(
        (e) => e.name == row.priority,
        orElse: () => TicketPriority.none,
      ),
      parentId: row.parentId,
      embedding: row.embedding,
      estimate: row.estimate,
      timeSpent: row.timeSpent,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
      deletedAt: row.deletedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.deletedAt!),
    );
  }
}
