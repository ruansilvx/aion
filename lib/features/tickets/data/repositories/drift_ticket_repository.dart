// data/repositories/drift_ticket_repository.dart — Drift implementation of TicketRepository (data layer).

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/exceptions/ticket_has_children_exception.dart';
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

  @override
  Future<void> deleteTicket(String id) async {
    final existing = await _db.ticketDao.getTicketById(id);
    if (existing == null) {
      throw StateError('Ticket $id does not exist');
    }

    final childCount = await _db.ticketDao.countChildTickets(id);
    if (childCount > 0) {
      throw TicketHasChildrenException(childCount);
    }

    await _db.transaction(() async {
      await _db.commentDao.deleteCommentsForTicket(id);
      await _db.ticketLinkDao.deleteLinksForTicket(id);
      await _db.ticketDao.deleteTicketRow(id);
    });
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
    );
  }
}
