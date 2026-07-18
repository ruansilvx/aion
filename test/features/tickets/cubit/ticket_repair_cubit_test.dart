import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/tickets/data/services/ticket_repair_service.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_repair_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_repair_state.dart';

class MockTicketRepairService extends Mock implements TicketRepairService {}

void main() {
  late MockTicketRepairService service;

  setUp(() {
    service = MockTicketRepairService();
  });

  group('reformat', () {
    blocTest<TicketRepairCubit, TicketRepairState>(
      'emits [InProgress, Completed] when the service reports success',
      setUp: () => when(
        () => service.reformat('AIO-1', '/root'),
      ).thenAnswer((_) async => true),
      build: () => TicketRepairCubit(service, 'AIO-1', '/root'),
      act: (cubit) => cubit.reformat(),
      expect: () => [
        const TicketRepairInProgress(),
        isA<TicketRepairCompleted>(),
      ],
    );

    blocTest<TicketRepairCubit, TicketRepairState>(
      'emits [InProgress, Failed] when the service reports failure',
      setUp: () => when(
        () => service.reformat('AIO-1', '/root'),
      ).thenAnswer((_) async => false),
      build: () => TicketRepairCubit(service, 'AIO-1', '/root'),
      act: (cubit) => cubit.reformat(),
      expect: () => [
        const TicketRepairInProgress(),
        isA<TicketRepairFailed>(),
      ],
    );

    blocTest<TicketRepairCubit, TicketRepairState>(
      'emits [InProgress, Failed] when the service throws',
      setUp: () => when(
        () => service.reformat('AIO-1', '/root'),
      ).thenThrow(Exception('boom')),
      build: () => TicketRepairCubit(service, 'AIO-1', '/root'),
      act: (cubit) => cubit.reformat(),
      expect: () => [
        const TicketRepairInProgress(),
        isA<TicketRepairFailed>(),
      ],
    );
  });

  group('restoreFromLastKnownGood', () {
    blocTest<TicketRepairCubit, TicketRepairState>(
      'emits [InProgress, Completed] on success',
      setUp: () => when(
        () => service.restoreFromLastKnownGood('AIO-1', '/root'),
      ).thenAnswer((_) async {}),
      build: () => TicketRepairCubit(service, 'AIO-1', '/root'),
      act: (cubit) => cubit.restoreFromLastKnownGood(),
      expect: () => [
        const TicketRepairInProgress(),
        isA<TicketRepairCompleted>(),
      ],
    );

    blocTest<TicketRepairCubit, TicketRepairState>(
      'emits [InProgress, Failed] when the service throws',
      setUp: () => when(
        () => service.restoreFromLastKnownGood('AIO-1', '/root'),
      ).thenThrow(Exception('boom')),
      build: () => TicketRepairCubit(service, 'AIO-1', '/root'),
      act: (cubit) => cubit.restoreFromLastKnownGood(),
      expect: () => [
        const TicketRepairInProgress(),
        isA<TicketRepairFailed>(),
      ],
    );
  });
}
