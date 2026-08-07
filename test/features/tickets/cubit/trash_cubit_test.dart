import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockTicketGitProjector extends Mock implements TicketGitProjector {}

void main() {
  late MockTicketRepository repository;
  late MockTicketGitProjector gitProjector;

  Ticket buildTrashed({
    required String id,
    String? parentId,
    DateTime? deletedAt,
  }) {
    final now = DateTime(2026, 1, 1);
    return Ticket(
      id: id,
      ticketId: 'AIO-$id',
      type: TicketType.task,
      title: 'Trashed $id',
      status: TicketStatus.backlog,
      parentId: parentId,
      createdAt: now,
      updatedAt: now,
      deletedAt: deletedAt ?? now,
    );
  }

  setUpAll(() {
    registerFallbackValue(buildTrashed(id: 'fallback'));
  });

  setUp(() {
    repository = MockTicketRepository();
    gitProjector = MockTicketGitProjector();
  });

  group('TrashCubit', () {
    blocTest<TrashCubit, TrashState>(
      'load emits [TrashLoading, TrashLoaded] with a childless trashed '
      'ticket as its own root and zero descendants',
      setUp: () {
        final trashed = buildTrashed(
          id: '1',
          deletedAt: DateTime.now().subtract(const Duration(days: 100)),
        );
        when(
          () => repository.getTrashedTickets(),
        ).thenAnswer((_) async => [trashed]);
      },
      build: () => TrashCubit(repository),
      act: (cubit) => cubit.load(),
      expect: () => [
        const TrashLoading(),
        isA<TrashLoaded>()
            .having((s) => s.tickets.map((t) => t.id), 'root ids', ['1'])
            .having(
              (s) => s.descendantCounts['1'],
              'descendant count for 1',
              0,
            )
            .having(
              (s) => s.purgeEligibleCount,
              'purge eligible count',
              1,
            ),
      ],
    );

    blocTest<TrashCubit, TrashState>(
      'load folds a cascaded descendant into its root, not its own tile, '
      'and counts it',
      setUp: () {
        final oldDeletedAt = DateTime.now().subtract(
          const Duration(days: 100),
        );
        final root = buildTrashed(id: 'root', deletedAt: oldDeletedAt);
        final child = buildTrashed(
          id: 'child',
          parentId: 'root',
          deletedAt: oldDeletedAt,
        );
        final grandchild = buildTrashed(
          id: 'grandchild',
          parentId: 'child',
          deletedAt: oldDeletedAt,
        );
        when(
          () => repository.getTrashedTickets(),
        ).thenAnswer((_) async => [root, child, grandchild]);
      },
      build: () => TrashCubit(repository),
      act: (cubit) => cubit.load(),
      expect: () => [
        const TrashLoading(),
        isA<TrashLoaded>()
            .having((s) => s.tickets.map((t) => t.id), 'root ids', ['root'])
            .having(
              (s) => s.descendantCounts['root'],
              'descendant count for root',
              2,
            )
            .having(
              (s) => s.purgeEligibleCount,
              'purge eligible count',
              3,
            ),
      ],
    );

    blocTest<TrashCubit, TrashState>(
      'load computes purgeEligibleCount from a mix of old and young '
      'trashed tickets',
      setUp: () {
        final old = buildTrashed(
          id: 'old',
          deletedAt: DateTime.now().subtract(const Duration(days: 45)),
        );
        final young = buildTrashed(
          id: 'young',
          deletedAt: DateTime.now().subtract(const Duration(days: 5)),
        );
        when(
          () => repository.getTrashedTickets(),
        ).thenAnswer((_) async => [old, young]);
      },
      build: () => TrashCubit(repository),
      act: (cubit) => cubit.load(),
      expect: () => [
        const TrashLoading(),
        isA<TrashLoaded>().having(
          (s) => s.purgeEligibleCount,
          'purge eligible count',
          1,
        ),
      ],
    );

    blocTest<TrashCubit, TrashState>(
      'load emits [TrashLoading, TrashError] when the repository throws',
      setUp: () {
        when(() => repository.getTrashedTickets()).thenThrow(Exception('boom'));
      },
      build: () => TrashCubit(repository),
      act: (cubit) => cubit.load(),
      expect: () => [const TrashLoading(), isA<TrashError>()],
    );

    blocTest<TrashCubit, TrashState>(
      'restore calls the repository then reloads',
      setUp: () {
        when(() => repository.restoreTicket('1')).thenAnswer((_) async {});
        when(
          () => repository.getTicketById('1'),
        ).thenAnswer((_) async => buildTrashed(id: '1', deletedAt: null));
        when(() => repository.getTrashedTickets()).thenAnswer((_) async => []);
      },
      build: () => TrashCubit(repository),
      act: (cubit) => cubit.restore('1'),
      verify: (_) {
        verify(() => repository.restoreTicket('1')).called(1);
      },
      expect: () => [
        const TrashLoading(),
        const TrashLoaded([], {}, 0),
      ],
    );

    blocTest<TrashCubit, TrashState>(
      'restore emits TrashError when the repository throws',
      setUp: () {
        when(
          () => repository.restoreTicket('1'),
        ).thenThrow(Exception('boom'));
      },
      build: () => TrashCubit(repository),
      act: (cubit) => cubit.restore('1'),
      expect: () => [isA<TrashError>()],
    );

    group('restore git-projection trigger', () {
      final restoredTicket = buildTrashed(id: '1', deletedAt: null);

      blocTest<TrashCubit, TrashState>(
        'restore projects the restored ticket labelled "restored" when '
        'gitProjector/projectRootPath are supplied',
        setUp: () {
          when(() => repository.restoreTicket('1')).thenAnswer((_) async {});
          when(
            () => repository.getTicketById('1'),
          ).thenAnswer((_) async => restoredTicket);
          when(
            () => repository.getTrashedTickets(),
          ).thenAnswer((_) async => []);
          when(
            () => gitProjector.project(any(), any(), any()),
          ).thenAnswer((_) async {});
        },
        build: () => TrashCubit(
          repository,
          gitProjector: gitProjector,
          projectRootPath: '/root',
        ),
        act: (cubit) => cubit.restore('1'),
        verify: (_) {
          verify(
            () => gitProjector.project(restoredTicket, '/root', 'restored'),
          ).called(1);
        },
        expect: () => [
          const TrashLoading(),
          const TrashLoaded([], {}, 0),
        ],
      );

      blocTest<TrashCubit, TrashState>(
        'restore never calls the projector when gitProjector/projectRootPath '
        'are omitted',
        setUp: () {
          when(() => repository.restoreTicket('1')).thenAnswer((_) async {});
          when(
            () => repository.getTicketById('1'),
          ).thenAnswer((_) async => restoredTicket);
          when(
            () => repository.getTrashedTickets(),
          ).thenAnswer((_) async => []);
        },
        build: () => TrashCubit(repository),
        act: (cubit) => cubit.restore('1'),
        verify: (_) {
          verifyNever(() => gitProjector.project(any(), any(), any()));
        },
        expect: () => [
          const TrashLoading(),
          const TrashLoaded([], {}, 0),
        ],
      );
    });

    blocTest<TrashCubit, TrashState>(
      'permanentlyDelete calls the repository then reloads',
      setUp: () {
        when(
          () => repository.permanentlyDeleteTicket('1'),
        ).thenAnswer((_) async {});
        when(() => repository.getTrashedTickets()).thenAnswer((_) async => []);
      },
      build: () => TrashCubit(repository),
      act: (cubit) => cubit.permanentlyDelete('1'),
      verify: (_) {
        verify(() => repository.permanentlyDeleteTicket('1')).called(1);
      },
      expect: () => [
        const TrashLoading(),
        const TrashLoaded([], {}, 0),
      ],
    );

    blocTest<TrashCubit, TrashState>(
      'permanentlyDelete emits TrashError when the repository throws',
      setUp: () {
        when(
          () => repository.permanentlyDeleteTicket('1'),
        ).thenThrow(Exception('boom'));
      },
      build: () => TrashCubit(repository),
      act: (cubit) => cubit.permanentlyDelete('1'),
      expect: () => [isA<TrashError>()],
    );

    blocTest<TrashCubit, TrashState>(
      'emptyTrash calls the repository then reloads',
      setUp: () {
        when(() => repository.emptyTrash()).thenAnswer((_) async {});
        when(() => repository.getTrashedTickets()).thenAnswer((_) async => []);
      },
      build: () => TrashCubit(repository),
      act: (cubit) => cubit.emptyTrash(),
      verify: (_) {
        verify(() => repository.emptyTrash()).called(1);
      },
      expect: () => [
        const TrashLoading(),
        const TrashLoaded([], {}, 0),
      ],
    );

    blocTest<TrashCubit, TrashState>(
      'emptyTrash emits TrashError when the repository throws',
      setUp: () {
        when(() => repository.emptyTrash()).thenThrow(Exception('boom'));
      },
      build: () => TrashCubit(repository),
      act: (cubit) => cubit.emptyTrash(),
      expect: () => [isA<TrashError>()],
    );

    blocTest<TrashCubit, TrashState>(
      'purgeOldTrash calls the repository then reloads',
      setUp: () {
        when(
          () => repository.purgeTrashOlderThan(TrashCubit.purgeAgeThreshold),
        ).thenAnswer((_) async => 2);
        when(() => repository.getTrashedTickets()).thenAnswer((_) async => []);
      },
      build: () => TrashCubit(repository),
      act: (cubit) => cubit.purgeOldTrash(),
      verify: (_) {
        verify(
          () => repository.purgeTrashOlderThan(TrashCubit.purgeAgeThreshold),
        ).called(1);
      },
      expect: () => [
        const TrashLoading(),
        const TrashLoaded([], {}, 0),
      ],
    );

    blocTest<TrashCubit, TrashState>(
      'purgeOldTrash emits TrashError when the repository throws',
      setUp: () {
        when(
          () => repository.purgeTrashOlderThan(TrashCubit.purgeAgeThreshold),
        ).thenThrow(Exception('boom'));
      },
      build: () => TrashCubit(repository),
      act: (cubit) => cubit.purgeOldTrash(),
      expect: () => [isA<TrashError>()],
    );
  });
}
