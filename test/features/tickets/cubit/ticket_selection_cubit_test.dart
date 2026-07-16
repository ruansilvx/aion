import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/features/tickets/tickets.dart';

void main() {
  group('TicketSelectionCubit', () {
    blocTest<TicketSelectionCubit, TicketSelectionState>(
      'enter emits an active, empty-selection state',
      build: () => TicketSelectionCubit(),
      act: (cubit) => cubit.enter(),
      expect: () => [
        const TicketSelectionState(isActive: true, selectedIds: {}),
      ],
    );

    blocTest<TicketSelectionCubit, TicketSelectionState>(
      'toggle adds an id when active and not yet selected',
      build: () => TicketSelectionCubit(),
      seed: () => const TicketSelectionState(isActive: true, selectedIds: {}),
      act: (cubit) => cubit.toggle('1'),
      expect: () => [
        const TicketSelectionState(isActive: true, selectedIds: {'1'}),
      ],
    );

    blocTest<TicketSelectionCubit, TicketSelectionState>(
      'toggle removes an id when active and already selected',
      build: () => TicketSelectionCubit(),
      seed: () =>
          const TicketSelectionState(isActive: true, selectedIds: {'1', '2'}),
      act: (cubit) => cubit.toggle('1'),
      expect: () => [
        const TicketSelectionState(isActive: true, selectedIds: {'2'}),
      ],
    );

    blocTest<TicketSelectionCubit, TicketSelectionState>(
      'toggle is a no-op while inactive',
      build: () => TicketSelectionCubit(),
      act: (cubit) => cubit.toggle('1'),
      expect: () => <TicketSelectionState>[],
    );

    blocTest<TicketSelectionCubit, TicketSelectionState>(
      'selectAll selects every id when not all are already selected',
      build: () => TicketSelectionCubit(),
      seed: () => const TicketSelectionState(isActive: true, selectedIds: {'1'}),
      act: (cubit) => cubit.selectAll(['1', '2', '3']),
      expect: () => [
        const TicketSelectionState(
          isActive: true,
          selectedIds: {'1', '2', '3'},
        ),
      ],
    );

    blocTest<TicketSelectionCubit, TicketSelectionState>(
      'selectAll deselects everything when all ids are already selected',
      build: () => TicketSelectionCubit(),
      seed: () => const TicketSelectionState(
        isActive: true,
        selectedIds: {'1', '2'},
      ),
      act: (cubit) => cubit.selectAll(['1', '2']),
      expect: () => [
        const TicketSelectionState(isActive: true, selectedIds: {}),
      ],
    );

    blocTest<TicketSelectionCubit, TicketSelectionState>(
      'selectAll with an empty ids list is a no-op-shaped all-deselected result',
      build: () => TicketSelectionCubit(),
      seed: () => const TicketSelectionState(isActive: true, selectedIds: {'1'}),
      act: (cubit) => cubit.selectAll([]),
      expect: () => [
        const TicketSelectionState(isActive: true, selectedIds: {}),
      ],
    );

    blocTest<TicketSelectionCubit, TicketSelectionState>(
      'clear resets to the initial inactive, empty-selection state',
      build: () => TicketSelectionCubit(),
      seed: () => const TicketSelectionState(
        isActive: true,
        selectedIds: {'1', '2'},
      ),
      act: (cubit) => cubit.clear(),
      expect: () => [const TicketSelectionState.initial()],
    );
  });
}
