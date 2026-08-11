import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/git/git_repository_client.dart';
import 'package:aion/core/markdown/ticket_markdown_serializer.dart';
import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockGitRepositoryClient extends Mock implements GitRepositoryClient {}

void main() {
  late MockGitRepositoryClient git;
  late TicketGitProjector projector;
  late Directory tempDir;

  final ticket = Ticket(
    id: 'internal-1',
    ticketId: 'AIO-42',
    type: TicketType.task,
    title: 'A task',
    description: 'Description.',
    status: TicketStatus.backlog,
    createdAt: DateTime.utc(2026, 7, 18),
    updatedAt: DateTime.utc(2026, 7, 18),
  );

  setUp(() async {
    git = MockGitRepositoryClient();
    projector = TicketGitProjector(TicketMarkdownSerializer(), git);
    tempDir = await Directory.systemTemp.createTemp('ticket_git_projector_test');
    when(() => git.add(any(), any())).thenAnswer((_) async {});
    when(() => git.commit(any(), any())).thenAnswer((_) async {});
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('writes the expected file content', () async {
    when(() => git.hasChanges(any())).thenAnswer((_) async => true);

    await projector.project(ticket, tempDir.path, 'created');

    final file = File('${tempDir.path}/tickets/AIO-42.md');
    expect(await file.exists(), isTrue);
    final content = await file.readAsString();
    expect(content, contains('ticketId: AIO-42'));
    expect(content, contains('# A task'));
    expect(content, contains('Description.'));
  });

  test('adds and commits with an event-labelled message when changed', () async {
    when(() => git.hasChanges(any())).thenAnswer((_) async => true);

    await projector.project(ticket, tempDir.path, 'status-changed');

    verify(() => git.add(tempDir.path, 'tickets/AIO-42.md')).called(1);
    verify(() => git.commit(tempDir.path, 'ticket: AIO-42 status-changed'))
        .called(1);
  });

  test('skips the commit when hasChanges is false', () async {
    when(() => git.hasChanges(any())).thenAnswer((_) async => false);

    await projector.project(ticket, tempDir.path, 'created');

    verify(() => git.add(any(), any())).called(1);
    verifyNever(() => git.commit(any(), any()));
  });

  group('projectBatch', () {
    final secondTicket = Ticket(
      id: 'internal-2',
      ticketId: 'AIO-43',
      type: TicketType.story,
      title: 'A story',
      status: TicketStatus.backlog,
      createdAt: DateTime.utc(2026, 7, 18),
      updatedAt: DateTime.utc(2026, 7, 18),
    );

    test('writes N files and makes exactly one commit', () async {
      when(() => git.hasChanges(any())).thenAnswer((_) async => true);

      await projector.projectBatch(
        [ticket, secondTicket],
        tempDir.path,
        'rollup updated',
      );

      final firstFile = File('${tempDir.path}/tickets/AIO-42.md');
      final secondFile = File('${tempDir.path}/tickets/AIO-43.md');
      expect(await firstFile.exists(), isTrue);
      expect(await secondFile.exists(), isTrue);
      final secondContent = await secondFile.readAsString();
      expect(secondContent, contains('ticketId: AIO-43'));
      expect(secondContent, contains('# A story'));

      verify(() => git.add(tempDir.path, 'tickets/AIO-42.md')).called(1);
      verify(() => git.add(tempDir.path, 'tickets/AIO-43.md')).called(1);
      verify(
        () => git.commit(tempDir.path, 'ticket: 2 ancestors rollup updated'),
      ).called(1);
    });

    test('no-ops (writes nothing, commits nothing) on an empty list', () async {
      await projector.projectBatch([], tempDir.path, 'rollup updated');

      verifyNever(() => git.add(any(), any()));
      verifyNever(() => git.commit(any(), any()));
      verifyNever(() => git.hasChanges(any()));
    });

    test(
      'skips the commit (but still writes files) when hasChanges is false',
      () async {
        when(() => git.hasChanges(any())).thenAnswer((_) async => false);

        await projector.projectBatch(
          [ticket, secondTicket],
          tempDir.path,
          'rollup updated',
        );

        expect(await File('${tempDir.path}/tickets/AIO-42.md').exists(), isTrue);
        expect(await File('${tempDir.path}/tickets/AIO-43.md').exists(), isTrue);
        verify(() => git.add(any(), any())).called(2);
        verifyNever(() => git.commit(any(), any()));
      },
    );

    test('a single-ticket batch uses the ticketId singular label', () async {
      when(() => git.hasChanges(any())).thenAnswer((_) async => true);

      await projector.projectBatch([ticket], tempDir.path, 'rollup updated');

      verify(
        () => git.commit(tempDir.path, 'ticket: AIO-42 rollup updated'),
      ).called(1);
    });
  });

  group('against a real git repository (the bug this fixes)', () {
    // The tests above mock `GitRepositoryClient.hasChanges` directly, so
    // they can't exercise the actual defect
    // `git-projection-commit-visibility` fixes — it lived entirely in
    // whether `deletedAt` was serialized at all, not in
    // `TicketGitProjector`'s own logic. A real `GitRepositoryClient`
    // against a real temp git repo is needed to prove a real `git diff`
    // is produced.
    late Directory realRepoDir;
    late TicketGitProjector realProjector;

    setUp(() async {
      realRepoDir = await Directory.systemTemp.createTemp(
        'ticket_git_projector_real_test',
      );
      await Process.run('git', ['init'], workingDirectory: realRepoDir.path);
      realProjector = TicketGitProjector(
        TicketMarkdownSerializer(),
        GitRepositoryClient(),
      );
    });

    tearDown(() async {
      await realRepoDir.delete(recursive: true);
    });

    Future<int> commitCount() async {
      final result = await Process.run(
        'git',
        ['log', '--oneline'],
        workingDirectory: realRepoDir.path,
      );
      final output = result.stdout.toString().trim();
      return output.isEmpty ? 0 : output.split('\n').length;
    }

    test(
      'a real commit lands when only deletedAt changes between projections',
      () async {
        await realProjector.project(ticket, realRepoDir.path, 'created');
        expect(await commitCount(), 1);

        final trashed = Ticket(
          id: ticket.id,
          ticketId: ticket.ticketId,
          type: ticket.type,
          title: ticket.title,
          description: ticket.description,
          status: ticket.status,
          createdAt: ticket.createdAt,
          updatedAt: ticket.updatedAt,
          deletedAt: DateTime.utc(2026, 8, 1),
        );
        await realProjector.project(trashed, realRepoDir.path, 'trashed');
        expect(
          await commitCount(),
          2,
          reason:
              'trashing changed deletedAt, so a real diff exists and the '
              'commit should not be skipped — this is the exact case that '
              'silently no-op\'d before deletedAt was serialized',
        );

        final restored = Ticket(
          id: ticket.id,
          ticketId: ticket.ticketId,
          type: ticket.type,
          title: ticket.title,
          description: ticket.description,
          status: ticket.status,
          createdAt: ticket.createdAt,
          updatedAt: ticket.updatedAt,
          deletedAt: null,
        );
        await realProjector.project(restored, realRepoDir.path, 'restored');
        expect(
          await commitCount(),
          3,
          reason:
              'restoring changed deletedAt back to null, another real diff',
        );

        // Projecting the exact same (already-restored) ticket again with
        // no field changes at all should still correctly no-op — the
        // pre-existing "no empty commits" behavior must survive this fix.
        await realProjector.project(restored, realRepoDir.path, 'restored');
        expect(await commitCount(), 3);
      },
    );
  });
}
