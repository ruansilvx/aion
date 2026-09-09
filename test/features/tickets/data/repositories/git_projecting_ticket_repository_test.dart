import 'dart:io' show Directory, File, Process, ProcessException;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_repository.dart';
import 'package:aion/features/tickets/data/repositories/git_projecting_ticket_repository.dart';
import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockTicketGitProjector extends Mock implements TicketGitProjector {}

void main() {
  late MockTicketRepository inner;
  late MockTicketGitProjector projector;
  late GitProjectingTicketRepository repository;

  const rootPath = '/root';

  final ticket = Ticket(
    id: '1',
    ticketId: 'AIO-1',
    type: TicketType.task,
    title: 'Test ticket',
    status: 'backlog',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUpAll(() {
    registerFallbackValue(ticket);
    registerFallbackValue(<Ticket>[]);
  });

  setUp(() {
    inner = MockTicketRepository();
    projector = MockTicketGitProjector();
    repository = GitProjectingTicketRepository(inner, projector, rootPath);
    when(
      () => projector.project(any(), any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => projector.projectBatch(any(), any(), any()),
    ).thenAnswer((_) async {});
    when(() => inner.getTicketById(ticket.id)).thenAnswer((_) async => ticket);
  });

  group('projected methods', () {
    test('createTicket delegates then projects "created"', () async {
      when(() => inner.createTicket(ticket)).thenAnswer((_) async {});

      await repository.createTicket(ticket);
      // The projection is fired unawaited — pump the event queue once so
      // the fire-and-forget Future has a chance to complete before
      // asserting on it.
      await pumpEventQueue();

      verify(() => inner.createTicket(ticket)).called(1);
      verify(() => projector.project(ticket, rootPath, 'created')).called(1);
    });

    test(
      'updateTicketStatus delegates then projects "status-changed"',
      () async {
        when(
          () => inner.updateTicketStatus(ticket.id, 'done'),
        ).thenAnswer((_) async {});

        await repository.updateTicketStatus(ticket.id, 'done');
        await pumpEventQueue();

        verify(() => inner.updateTicketStatus(ticket.id, 'done')).called(1);
        verify(
          () => projector.project(ticket, rootPath, 'status-changed'),
        ).called(1);
      },
    );

    test(
      'updateStatusForIds delegates then projects "status-changed" once '
      'per id',
      () async {
        final other = Ticket(
          id: '2',
          ticketId: 'AIO-2',
          type: TicketType.task,
          title: 'Other ticket',
          status: 'backlog',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        when(
          () => inner.updateStatusForIds([ticket.id, other.id], 'done'),
        ).thenAnswer((_) async {});
        when(
          () => inner.getTicketById(other.id),
        ).thenAnswer((_) async => other);

        await repository.updateStatusForIds([ticket.id, other.id], 'done');
        await pumpEventQueue();

        verify(
          () => projector.project(ticket, rootPath, 'status-changed'),
        ).called(1);
        verify(
          () => projector.project(other, rootPath, 'status-changed'),
        ).called(1);
      },
    );

    test(
      'updateTicketSddStage delegates then projects "stage-changed"',
      () async {
        when(
          () => inner.updateTicketSddStage(ticket.id, SddStage.exploring),
        ).thenAnswer((_) async {});

        await repository.updateTicketSddStage(ticket.id, SddStage.exploring);
        await pumpEventQueue();

        verify(
          () => inner.updateTicketSddStage(ticket.id, SddStage.exploring),
        ).called(1);
        verify(
          () => projector.project(ticket, rootPath, 'stage-changed'),
        ).called(1);
      },
    );

    test('updateTicketParent delegates then projects "reparented"', () async {
      when(
        () => inner.updateTicketParent(ticket.id, 'parent-1'),
      ).thenAnswer((_) async {});

      await repository.updateTicketParent(ticket.id, 'parent-1');
      await pumpEventQueue();

      verify(
        () => inner.updateTicketParent(ticket.id, 'parent-1'),
      ).called(1);
      verify(
        () => projector.project(ticket, rootPath, 'reparented'),
      ).called(1);
    });

    test(
      'trashTicket delegates then awaits a batched "trashed" projection '
      'of every id it reports as affected, before returning',
      () async {
        when(
          () => inner.trashTicket(ticket.id),
        ).thenAnswer((_) async => [ticket.id]);

        final affected = await repository.trashTicket(ticket.id);

        expect(affected, [ticket.id]);
        verify(() => inner.trashTicket(ticket.id)).called(1);
        // No `pumpEventQueue()` needed here — unlike the fire-and-forget
        // methods above, trashTicket awaits its own projection call, so
        // it's already complete by the time `await` above returns.
        verify(
          () => projector.projectBatch([ticket], rootPath, 'trashed'),
        ).called(1);
        verifyNever(() => projector.project(any(), any(), any()));
      },
    );

    test(
      'restoreTicket delegates then awaits a batched "restored" '
      'projection of every id it reports as affected, before returning',
      () async {
        when(
          () => inner.restoreTicket(ticket.id),
        ).thenAnswer((_) async => [ticket.id]);

        final affected = await repository.restoreTicket(ticket.id);

        expect(affected, [ticket.id]);
        verify(() => inner.restoreTicket(ticket.id)).called(1);
        verify(
          () => projector.projectBatch([ticket], rootPath, 'restored'),
        ).called(1);
        verifyNever(() => projector.project(any(), any(), any()));
      },
    );

    test(
      'trashTicket batch-projects every cascaded id its inner call '
      'reports — not just the id it was called with',
      () async {
        final child = Ticket(
          id: '2',
          ticketId: 'AIO-2',
          type: TicketType.task,
          title: 'Cascaded descendant',
          status: 'backlog',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        when(
          () => inner.trashTicket(ticket.id),
        ).thenAnswer((_) async => [ticket.id, child.id]);
        when(
          () => inner.getTicketById(child.id),
        ).thenAnswer((_) async => child);

        final affected = await repository.trashTicket(ticket.id);

        expect(affected, [ticket.id, child.id]);
        verify(
          () => projector.projectBatch([ticket, child], rootPath, 'trashed'),
        ).called(1);
      },
    );

    test(
      'trashTicket drops a cascaded id from the batch if it no longer '
      'resolves to a ticket, without failing the whole batch',
      () async {
        when(
          () => inner.trashTicket(ticket.id),
        ).thenAnswer((_) async => [ticket.id, 'vanished']);
        when(
          () => inner.getTicketById('vanished'),
        ).thenAnswer((_) async => null);

        await repository.trashTicket(ticket.id);

        verify(
          () => projector.projectBatch([ticket], rootPath, 'trashed'),
        ).called(1);
      },
    );

    test(
      'trashTicket does not propagate a ProcessException from the '
      'projector — the trash above already succeeded and must not be '
      'reported as an error',
      () async {
        when(
          () => inner.trashTicket(ticket.id),
        ).thenAnswer((_) async => [ticket.id]);
        when(
          () => projector.projectBatch([ticket], rootPath, 'trashed'),
        ).thenThrow(ProcessException('git', ['commit'], 'boom', 128));

        // Must complete normally (not throw) despite the projector
        // throwing — trashTicket already succeeded via `inner` above.
        await repository.trashTicket(ticket.id);

        verify(() => inner.trashTicket(ticket.id)).called(1);
      },
    );

    test(
      'restoreTicket does not propagate a ProcessException from the '
      'projector — the restore above already succeeded and must not be '
      'reported as an error',
      () async {
        when(
          () => inner.restoreTicket(ticket.id),
        ).thenAnswer((_) async => [ticket.id]);
        when(
          () => projector.projectBatch([ticket], rootPath, 'restored'),
        ).thenThrow(ProcessException('git', ['commit'], 'boom', 128));

        await repository.restoreTicket(ticket.id);

        verify(() => inner.restoreTicket(ticket.id)).called(1);
      },
    );

    test(
      'trashTicket still propagates an exception that is not a '
      'ProcessException/FileSystemException — only the two failure '
      'types git projection can actually throw are swallowed',
      () async {
        when(
          () => inner.trashTicket(ticket.id),
        ).thenAnswer((_) async => [ticket.id]);
        when(
          () => projector.projectBatch([ticket], rootPath, 'trashed'),
        ).thenThrow(StateError('an unrelated bug, not a git failure'));

        await expectLater(
          repository.trashTicket(ticket.id),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'no-ops projection when the ticket no longer exists after the write',
      () async {
        when(
          () => inner.getTicketById(ticket.id),
        ).thenAnswer((_) async => null);
        when(() => inner.createTicket(ticket)).thenAnswer((_) async {});

        await repository.createTicket(ticket);
        await pumpEventQueue();

        verifyNever(() => projector.project(any(), any(), any()));
      },
    );
  });

  group('pass-through methods (no projection)', () {
    test('updateTicket does not project', () async {
      when(() => inner.updateTicket(ticket)).thenAnswer((_) async {});

      await repository.updateTicket(ticket);
      await pumpEventQueue();

      verify(() => inner.updateTicket(ticket)).called(1);
      verifyNever(() => projector.project(any(), any(), any()));
    });

    test('updatePriorityForIds does not project', () async {
      when(
        () => inner.updatePriorityForIds([ticket.id], TicketPriority.high),
      ).thenAnswer((_) async {});

      await repository.updatePriorityForIds([ticket.id], TicketPriority.high);
      await pumpEventQueue();

      verifyNever(() => projector.project(any(), any(), any()));
    });

    test('addTimeSpent does not project', () async {
      when(
        () => inner.addTimeSpent(ticket.id, 30),
      ).thenAnswer((_) async {});

      await repository.addTimeSpent(ticket.id, 30);
      await pumpEventQueue();

      verifyNever(() => projector.project(any(), any(), any()));
    });

    test('applyEstimationSuggestion does not project', () async {
      when(
        () => inner.applyEstimationSuggestion(ticket.id),
      ).thenAnswer((_) async {});

      await repository.applyEstimationSuggestion(ticket.id);
      await pumpEventQueue();

      verifyNever(() => projector.project(any(), any(), any()));
    });

    test('updateRollup does not project (owned by TicketRollupRecomputer '
        "'s own batched projectBatch call)", () async {
      when(
        () => inner.updateRollup(
          ticket.id,
          estimateRollup: 5,
          timeSpentRollup: 5,
        ),
      ).thenAnswer((_) async {});

      await repository.updateRollup(
        ticket.id,
        estimateRollup: 5,
        timeSpentRollup: 5,
      );
      await pumpEventQueue();

      verifyNever(() => projector.project(any(), any(), any()));
      verifyNever(() => projector.projectBatch(any(), any(), any()));
    });

    test('importTicket does not project', () async {
      when(() => inner.importTicket(ticket)).thenAnswer((_) async {});

      await repository.importTicket(ticket);
      await pumpEventQueue();

      verifyNever(() => projector.project(any(), any(), any()));
    });

    test('permanentlyDeleteTicket does not project', () async {
      when(
        () => inner.permanentlyDeleteTicket(ticket.id),
      ).thenAnswer((_) async {});

      await repository.permanentlyDeleteTicket(ticket.id);
      await pumpEventQueue();

      verifyNever(() => projector.project(any(), any(), any()));
    });

    test('getAllTickets delegates without touching the projector', () async {
      when(() => inner.getAllTickets()).thenAnswer((_) async => [ticket]);

      final result = await repository.getAllTickets();

      expect(result, [ticket]);
      verifyNever(() => projector.project(any(), any(), any()));
    });
  });

  group('against a real repository, projector, and git repo (SUGGESTION '
      'from /verify: prove the whole cascade → one-commit chain end to '
      'end, not just at each layer in isolation)', () {
    late AppDatabase database;
    late GitProjectingTicketRepository realRepository;
    late Directory realRepoDir;

    setUp(() async {
      database = AppDatabase(
        Project(
          id: 'test-project',
          name: 'Test Project',
          storageKey: 'test-project',
          baselineVersion: '0.1.0',
          createdAt: DateTime(2024, 1, 1),
          lastOpenedAt: DateTime(2024, 1, 1),
        ),
        NativeDatabase.memory(),
      );
      realRepoDir = await Directory.systemTemp.createTemp(
        'git_projecting_ticket_repository_real_test',
      );
      await Process.run('git', ['init'], workingDirectory: realRepoDir.path);
      realRepository = GitProjectingTicketRepository(
        DriftTicketRepository(database),
        TicketGitProjector(TicketMarkdownSerializer(), GitRepositoryClient()),
        realRepoDir.path,
      );
    });

    tearDown(() async {
      await database.close();
      await realRepoDir.delete(recursive: true);
    });

    Future<List<String>> commitSubjects() async {
      final result = await Process.run(
        'git',
        ['log', '--format=%s'],
        workingDirectory: realRepoDir.path,
      );
      final output = result.stdout.toString().trim();
      return output.isEmpty ? [] : output.split('\n');
    }

    test(
      'restoring only a child produces one commit covering both the '
      "child and its silently-cascaded parent — not a missing commit "
      "for the parent (the AIO-2703/2704 incident this proposal fixes)",
      () async {
        await realRepository.importTicket(
          Ticket(
            id: 'epic-1',
            ticketId: 'AIO-1',
            type: TicketType.epic,
            title: 'Duplicate epic',
            status: 'backlog',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );
        await realRepository.importTicket(
          Ticket(
            id: 'child-1',
            ticketId: 'AIO-2',
            type: TicketType.task,
            title: 'Child',
            status: 'backlog',
            parentId: 'epic-1',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );

        await realRepository.trashTicket('epic-1');
        final afterTrash = await commitSubjects();
        expect(
          afterTrash.first,
          'ticket: 2 tickets trashed',
          reason:
              'one commit covering both the explicitly-trashed epic and '
              'its cascaded child',
        );

        await realRepository.restoreTicket('child-1');

        final epicFile = File('${realRepoDir.path}/tickets/AIO-1.md');
        expect(
          (await epicFile.readAsString()),
          contains('deletedAt: null'),
          reason:
              "restoring only the child must also re-project the epic it "
              "silently revived — the exact commit this proposal's "
              'cascade fix exists to produce.',
        );
        final subjects = await commitSubjects();
        expect(
          subjects.first,
          'ticket: 2 tickets restored',
          reason:
              'one commit covering both the explicitly-restored child '
              'and the epic its restore cascaded back to life',
        );
      },
    );
  });
}
