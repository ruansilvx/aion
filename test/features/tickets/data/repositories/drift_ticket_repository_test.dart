import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_repository.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late DriftTicketRepository repository;

  Ticket buildTicket({
    String id = '1',
    String title = 'Test ticket',
    TicketPriority priority = TicketPriority.none,
    int? estimate,
    int? timeSpent,
  }) {
    final now = DateTime(2026, 1, 1);
    return Ticket(
      id: id,
      ticketId: '',
      type: TicketType.task,
      title: title,
      status: TicketStatus.backlog,
      priority: priority,
      estimate: estimate,
      timeSpent: timeSpent,
      createdAt: now,
      updatedAt: now,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftTicketRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('createTicket then getAllTickets returns the created ticket', () async {
    await repository.createTicket(buildTicket());
    final tickets = await repository.getAllTickets();

    expect(tickets, hasLength(1));
    expect(tickets.first.title, 'Test ticket');
  });

  test('getTicketById returns correct ticket when found', () async {
    await repository.createTicket(buildTicket(id: 'abc'));
    final found = await repository.getTicketById('abc');

    expect(found, isNotNull);
    expect(found!.id, 'abc');
  });

  test('getTicketById returns null when not found', () async {
    final found = await repository.getTicketById('missing');
    expect(found, isNull);
  });

  test('enum round-trip: type, status, and priority survive write/read', () async {
    final now = DateTime(2026, 1, 1);
    final ticket = Ticket(
      id: '1',
      ticketId: '',
      type: TicketType.epic,
      title: 'Epic ticket',
      status: TicketStatus.inReview,
      priority: TicketPriority.critical,
      createdAt: now,
      updatedAt: now,
    );

    await repository.createTicket(ticket);
    final tickets = await repository.getAllTickets();

    expect(tickets.first.type, TicketType.epic);
    expect(tickets.first.status, TicketStatus.inReview);
    expect(tickets.first.priority, TicketPriority.critical);
  });

  test('priority defaults to TicketPriority.none when not supplied', () async {
    await repository.createTicket(buildTicket());
    final tickets = await repository.getAllTickets();

    expect(tickets.first.priority, TicketPriority.none);
  });

  test('estimate and time_spent nullable fields survive write/read', () async {
    await repository.createTicket(buildTicket(id: '1', estimate: null, timeSpent: null));
    await repository.createTicket(buildTicket(id: '2', estimate: 30, timeSpent: 15));

    final tickets = await repository.getAllTickets();
    final withNulls = tickets.firstWhere((t) => t.id == '1');
    final withValues = tickets.firstWhere((t) => t.id == '2');

    expect(withNulls.estimate, isNull);
    expect(withNulls.timeSpent, isNull);
    expect(withValues.estimate, 30);
    expect(withValues.timeSpent, 15);
  });

  test('first ticket generated ticketId is "AIO-1" (default prefix)', () async {
    await repository.createTicket(buildTicket());
    final tickets = await repository.getAllTickets();

    expect(tickets.first.ticketId, 'AIO-1');
  });

  test('second ticket generated ticketId is "AIO-2" (sequence increments)', () async {
    await repository.createTicket(buildTicket(id: '1'));
    await repository.createTicket(buildTicket(id: '2'));

    final tickets = await repository.getAllTickets();
    final ticketIds = tickets.map((t) => t.ticketId).toSet();

    expect(ticketIds, containsAll(['AIO-1', 'AIO-2']));
  });

  test('ticketId field survives entity mapping round-trip', () async {
    await repository.createTicket(buildTicket(id: 'xyz'));
    final found = await repository.getTicketById('xyz');

    expect(found!.ticketId, 'AIO-1');
  });
}
