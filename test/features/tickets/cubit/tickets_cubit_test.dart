import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

void main() {
  late MockTicketRepository repository;

  final ticket = Ticket(
    id: '1',
    ticketId: 'AIO-1',
    type: TicketType.task,
    title: 'Test ticket',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUpAll(() {
    registerFallbackValue(ticket);
  });

  setUp(() {
    repository = MockTicketRepository();
  });

  group('TicketsCubit', () {
    blocTest<TicketsCubit, TicketsState>(
      'loadTickets emits [TicketsLoading, TicketsLoaded] on success',
      setUp: () {
        when(() => repository.getAllTickets()).thenAnswer((_) async => [ticket]);
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.loadTickets(),
      expect: () => [
        const TicketsLoading(),
        TicketsLoaded([ticket]),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'loadTickets emits [TicketsLoading, TicketsError] on exception',
      setUp: () {
        when(() => repository.getAllTickets()).thenThrow(Exception('boom'));
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.loadTickets(),
      expect: () => [
        const TicketsLoading(),
        isA<TicketsError>(),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'createTicket emits [TicketCreating, TicketCreated] on success',
      setUp: () {
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        when(() => repository.getAllTickets()).thenAnswer((_) async => [ticket]);
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.createTicket(type: TicketType.task, title: 'New ticket'),
      expect: () => [
        const TicketCreating([]),
        TicketCreated([ticket]),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'createTicket emits [TicketCreating, TicketsError] on exception',
      setUp: () {
        when(() => repository.createTicket(any())).thenThrow(Exception('boom'));
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.createTicket(type: TicketType.task, title: 'New ticket'),
      expect: () => [
        const TicketCreating([]),
        isA<TicketsError>(),
      ],
    );
  });
}
