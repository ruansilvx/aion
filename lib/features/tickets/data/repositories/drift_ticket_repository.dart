import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';

class DriftTicketRepository implements TicketRepository {
  DriftTicketRepository(this._db);

  final AppDatabase _db;

  static const _prefixKey = 'ticket_id_prefix';
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
