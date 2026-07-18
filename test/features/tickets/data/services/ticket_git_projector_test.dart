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
}
