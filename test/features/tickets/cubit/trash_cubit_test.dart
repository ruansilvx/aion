import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_direction.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_field.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_list_sort_repository.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockTicketGitProjector extends Mock implements TicketGitProjector {}

class MockTicketListSortRepository extends Mock
    implements TicketListSortRepository {}

void main() {
  late MockTicketRepository repository;
  late MockTicketGitProjector gitProjector;
  late MockTicketListSortRepository sortRepository;

  Ticket buildTrashed({
    required String id,
    String? parentId,
    DateTime? deletedAt,
    DateTime? createdAt,
    TicketPriority priority = TicketPriority.none,
  }) {
    final now = DateTime(2026, 1, 1);
    return Ticket(
      id: id,
      ticketId: 'AIO-$id',
      type: TicketType.task,
      title: 'Trashed $id',
      status: 'backlog',
      priority: priority,
      parentId: parentId,
      createdAt: createdAt ?? now,
      updatedAt: createdAt ?? now,
      deletedAt: deletedAt ?? now,
    );
  }

  setUpAll(() {
    registerFallbackValue(buildTrashed(id: 'fallback'));
  });

  setUp(() {
    repository = MockTicketRepository();
    gitProjector = MockTicketGitProjector();
    sortRepository = MockTicketListSortRepository();
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
            .having((s) => s.descendantCounts['1'], 'descendant count for 1', 0)
            .having((s) => s.purgeEligibleCount, 'purge eligible count', 1),
      ],
    );

    blocTest<TrashCubit, TrashState>(
      'load folds a cascaded descendant into its root, not its own tile, '
      'and counts it',
      setUp: () {
        final oldDeletedAt = DateTime.now().subtract(const Duration(days: 100));
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
            .having((s) => s.purgeEligibleCount, 'purge eligible count', 3),
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

    group(
      'load — persisted sort (ticket-sort-control-and-board-as-default-view)',
      () {
        blocTest<TrashCubit, TrashState>(
          'load applies the persisted sort to roots',
          setUp: () {
            final low = buildTrashed(id: 'low', priority: TicketPriority.low);
            final critical = buildTrashed(
              id: 'critical',
              priority: TicketPriority.critical,
            );
            when(
              () => repository.getTrashedTickets(),
            ).thenAnswer((_) async => [low, critical]);
            when(() => sortRepository.getSort('proj-1')).thenAnswer(
              (_) async => const TicketListSort(
                field: TicketSortField.priority,
                direction: TicketSortDirection.ascending,
              ),
            );
          },
          build: () => TrashCubit(
            repository,
            sortRepository: sortRepository,
            projectId: 'proj-1',
          ),
          act: (cubit) => cubit.load(),
          expect: () => [
            const TrashLoading(),
            isA<TrashLoaded>().having(
              (s) => s.tickets.map((t) => t.id),
              'root ids',
              ['critical', 'low'],
            ),
          ],
        );

        blocTest<TrashCubit, TrashState>(
          'a persisted relevance sort falls back to createdAt descending — '
          'Trash has no query to score against',
          setUp: () {
            final older = buildTrashed(
              id: 'older',
              createdAt: DateTime(2026, 1, 1),
            );
            final newer = buildTrashed(
              id: 'newer',
              createdAt: DateTime(2026, 1, 2),
            );
            when(
              () => repository.getTrashedTickets(),
            ).thenAnswer((_) async => [older, newer]);
            when(() => sortRepository.getSort('proj-1')).thenAnswer(
              (_) async => const TicketListSort(
                field: TicketSortField.relevance,
                direction: TicketSortDirection.descending,
              ),
            );
          },
          build: () => TrashCubit(
            repository,
            sortRepository: sortRepository,
            projectId: 'proj-1',
          ),
          act: (cubit) => cubit.load(),
          expect: () => [
            const TrashLoading(),
            isA<TrashLoaded>().having(
              (s) => s.tickets.map((t) => t.id),
              'root ids',
              ['newer', 'older'],
            ),
          ],
        );

        blocTest<TrashCubit, TrashState>(
          'falls back to createdAt descending when sortRepository/projectId '
          'are not supplied',
          setUp: () {
            final older = buildTrashed(
              id: 'older',
              createdAt: DateTime(2026, 1, 1),
            );
            final newer = buildTrashed(
              id: 'newer',
              createdAt: DateTime(2026, 1, 2),
            );
            when(
              () => repository.getTrashedTickets(),
            ).thenAnswer((_) async => [older, newer]);
          },
          build: () => TrashCubit(repository),
          act: (cubit) => cubit.load(),
          expect: () => [
            const TrashLoading(),
            isA<TrashLoaded>().having(
              (s) => s.tickets.map((t) => t.id),
              'root ids',
              ['newer', 'older'],
            ),
          ],
        );
      },
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
      expect: () => [const TrashLoading(), const TrashLoaded([], {}, 0)],
    );

    blocTest<TrashCubit, TrashState>(
      'restore emits TrashError when the repository throws',
      setUp: () {
        when(() => repository.restoreTicket('1')).thenThrow(Exception('boom'));
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
        expect: () => [const TrashLoading(), const TrashLoaded([], {}, 0)],
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
        expect: () => [const TrashLoading(), const TrashLoaded([], {}, 0)],
      );
    });

    group(
      'restore rollup recompute '
      '(estimate-timespent-rollup-for-ticket-hierarchy)',
      () {
        final rollupParent = Ticket(
          id: 'rollup-restore-parent',
          ticketId: 'AIO-300',
          type: TicketType.story,
          title: 'Rollup restore parent',
          status: 'backlog',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          // Stale — needs to reflect the restored child's contribution
          // again, per the test below.
        );
        final restoredWithParent = Ticket(
          id: 'rollup-restored-child',
          ticketId: 'AIO-301',
          type: TicketType.task,
          title: 'Restored child',
          status: 'backlog',
          parentId: rollupParent.id,
          estimate: 45,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

        blocTest<TrashCubit, TrashState>(
          "restore triggers a rollup recompute of the restored ticket's "
          "parent chain, re-including the restored subtree's contribution",
          setUp: () {
            when(
              () => repository.restoreTicket(restoredWithParent.id),
            ).thenAnswer((_) async {});
            when(
              () => repository.getTicketById(restoredWithParent.id),
            ).thenAnswer((_) async => restoredWithParent);
            when(
              () => repository.getTrashedTickets(),
            ).thenAnswer((_) async => []);
            // Post-restore state: the child is live again, so it
            // contributes to rollupParent's rollup once more.
            when(() => repository.getAllTickets()).thenAnswer(
              (_) async => [rollupParent, restoredWithParent],
            );
            when(
              () => repository.updateRollup(
                any(),
                estimateRollup: any(named: 'estimateRollup'),
                timeSpentRollup: any(named: 'timeSpentRollup'),
              ),
            ).thenAnswer((_) async {});
          },
          build: () => TrashCubit(repository),
          act: (cubit) => cubit.restore(restoredWithParent.id),
          verify: (_) {
            verify(
              () => repository.updateRollup(
                rollupParent.id,
                estimateRollup: 45,
                timeSpentRollup: null,
              ),
            ).called(1);
          },
          expect: () => [const TrashLoading(), const TrashLoaded([], {}, 0)],
        );
      },
    );

    blocTest<TrashCubit, TrashState>(
      'restoreTickets calls TicketParentTrashService.restore once per id '
      '(not a batched repository call), reloads, and returns true',
      setUp: () {
        when(() => repository.restoreTicket(any())).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => buildTrashed(id: '1', deletedAt: null));
        when(() => repository.getTrashedTickets()).thenAnswer((_) async => []);
      },
      build: () => TrashCubit(repository),
      act: (cubit) => cubit.restoreTickets(['1', '2']),
      verify: (_) {
        verify(() => repository.restoreTicket('1')).called(1);
        verify(() => repository.restoreTicket('2')).called(1);
      },
      expect: () => [const TrashLoading(), const TrashLoaded([], {}, 0)],
    );

    test('restoreTickets returns true on success', () async {
      when(() => repository.restoreTicket(any())).thenAnswer((_) async {});
      when(
        () => repository.getTicketById(any()),
      ).thenAnswer((_) async => buildTrashed(id: '1', deletedAt: null));
      when(() => repository.getTrashedTickets()).thenAnswer((_) async => []);

      final cubit = TrashCubit(repository);
      expect(await cubit.restoreTickets(['1']), isTrue);
      await cubit.close();
    });

    blocTest<TrashCubit, TrashState>(
      'restoreTickets emits TrashError when the repository throws',
      setUp: () {
        when(() => repository.restoreTicket(any())).thenThrow(Exception('boom'));
      },
      build: () => TrashCubit(repository),
      act: (cubit) => cubit.restoreTickets(['1']),
      expect: () => [isA<TrashError>()],
    );

    test('restoreTickets returns false when the repository throws', () async {
      when(() => repository.restoreTicket(any())).thenThrow(Exception('boom'));

      final cubit = TrashCubit(repository);
      expect(await cubit.restoreTickets(['1']), isFalse);
      await cubit.close();
    });

    blocTest<TrashCubit, TrashState>(
      'permanentlyDeleteTickets calls the repository once with the full '
      'id list, reloads, and returns true',
      setUp: () {
        when(
          () => repository.permanentlyDeleteTickets(['1', '2']),
        ).thenAnswer((_) async => 2);
        when(() => repository.getTrashedTickets()).thenAnswer((_) async => []);
      },
      build: () => TrashCubit(repository),
      act: (cubit) => cubit.permanentlyDeleteTickets(['1', '2']),
      verify: (_) {
        verify(() => repository.permanentlyDeleteTickets(['1', '2'])).called(1);
      },
      expect: () => [const TrashLoading(), const TrashLoaded([], {}, 0)],
    );

    test('permanentlyDeleteTickets returns true on success', () async {
      when(
        () => repository.permanentlyDeleteTickets(any()),
      ).thenAnswer((_) async => 1);
      when(() => repository.getTrashedTickets()).thenAnswer((_) async => []);

      final cubit = TrashCubit(repository);
      expect(await cubit.permanentlyDeleteTickets(['1']), isTrue);
      await cubit.close();
    });

    blocTest<TrashCubit, TrashState>(
      'permanentlyDeleteTickets emits TrashError when the repository '
      'throws',
      setUp: () {
        when(
          () => repository.permanentlyDeleteTickets(any()),
        ).thenThrow(Exception('boom'));
      },
      build: () => TrashCubit(repository),
      act: (cubit) => cubit.permanentlyDeleteTickets(['1']),
      expect: () => [isA<TrashError>()],
    );

    test(
      'permanentlyDeleteTickets returns false when the repository throws',
      () async {
        when(
          () => repository.permanentlyDeleteTickets(any()),
        ).thenThrow(Exception('boom'));

        final cubit = TrashCubit(repository);
        expect(await cubit.permanentlyDeleteTickets(['1']), isFalse);
        await cubit.close();
      },
    );

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
      expect: () => [const TrashLoading(), const TrashLoaded([], {}, 0)],
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
      expect: () => [const TrashLoading(), const TrashLoaded([], {}, 0)],
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
      expect: () => [const TrashLoading(), const TrashLoaded([], {}, 0)],
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
