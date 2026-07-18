import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/core/markdown/ticket_markdown_serializer.dart';
import 'package:aion/features/tickets/data/services/ticket_db_reconstruction_service.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockEmbeddingProvider extends Mock implements EmbeddingProvider {}

void main() {
  late MockTicketRepository repository;
  late MockEmbeddingProvider embeddingProvider;
  late TicketDbReconstructionService service;
  late Directory tempDir;
  final serializer = TicketMarkdownSerializer();

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(
      Ticket(
        id: 'fallback',
        ticketId: 'FB-1',
        type: TicketType.task,
        title: 'fallback',
        status: TicketStatus.backlog,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
  });

  setUp(() async {
    repository = MockTicketRepository();
    embeddingProvider = MockEmbeddingProvider();
    service = TicketDbReconstructionService(repository, serializer, embeddingProvider);
    tempDir = await Directory.systemTemp.createTemp('ticket_db_reconstruction_test');
    await Directory('${tempDir.path}/tickets').create(recursive: true);

    when(() => repository.updateTicket(any())).thenAnswer((_) async {});
    when(() => repository.createTicket(any())).thenAnswer((_) async {});
    when(() => repository.updateEmbedding(any(), any())).thenAnswer((_) async {});
    when(() => embeddingProvider.embed(any())).thenAnswer(
      (_) async => Uint8List.fromList([9, 9, 9]),
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Ticket ticket({required String ticketId, required String title}) => Ticket(
    id: 'internal-$ticketId',
    ticketId: ticketId,
    type: TicketType.resource,
    title: title,
    description: 'Body for $ticketId.',
    status: TicketStatus.backlog,
    createdAt: DateTime.utc(2026, 7, 18),
    updatedAt: DateTime.utc(2026, 7, 18),
  );

  test('reports zero when tickets/ does not exist', () async {
    final emptyDir = await Directory.systemTemp.createTemp('no_tickets_dir');
    final report = await service.reconstruct(emptyDir.path);
    expect(report.importedCount, 0);
    expect(report.skippedPaths, isEmpty);
    await emptyDir.delete(recursive: true);
  });

  test('imports valid files as new tickets when no matching row exists', () async {
    when(() => repository.getAllTickets()).thenAnswer((_) async => []);
    await File('${tempDir.path}/tickets/AIO-1.md')
        .writeAsString(serializer.serialize(ticket(ticketId: 'AIO-1', title: 'One')));
    await File('${tempDir.path}/tickets/AIO-2.md')
        .writeAsString(serializer.serialize(ticket(ticketId: 'AIO-2', title: 'Two')));

    final report = await service.reconstruct(tempDir.path);

    expect(report.importedCount, 2);
    expect(report.skippedPaths, isEmpty);
    verify(() => repository.createTicket(any())).called(2);
    verifyNever(() => repository.updateTicket(any()));
  });

  test('updates the existing row when ticketId already has one', () async {
    final existing = ticket(ticketId: 'AIO-1', title: 'Old title');
    when(() => repository.getAllTickets()).thenAnswer((_) async => [existing]);
    await File('${tempDir.path}/tickets/AIO-1.md').writeAsString(
      serializer.serialize(existing.copyWith(title: 'New title')),
    );

    final report = await service.reconstruct(tempDir.path);

    expect(report.importedCount, 1);
    final captured = verify(() => repository.updateTicket(captureAny())).captured;
    final updated = captured.single as Ticket;
    expect(updated.id, existing.id, reason: 'must reuse the existing internal id');
    expect(updated.title, 'New title');
    verifyNever(() => repository.createTicket(any()));
  });

  test('skips and reports unparseable files without failing the run', () async {
    when(() => repository.getAllTickets()).thenAnswer((_) async => []);
    await File('${tempDir.path}/tickets/AIO-1.md')
        .writeAsString(serializer.serialize(ticket(ticketId: 'AIO-1', title: 'One')));
    await File('${tempDir.path}/tickets/broken.md').writeAsString('not valid at all');

    final report = await service.reconstruct(tempDir.path);

    expect(report.importedCount, 1);
    expect(report.skippedPaths.length, 1);
    expect(report.skippedPaths.single, contains('broken.md'));
  });

  test('bulk-backfills embeddings only for imported tickets lacking one', () async {
    when(() => repository.getAllTickets()).thenAnswer((_) async => []);
    await File('${tempDir.path}/tickets/AIO-1.md')
        .writeAsString(serializer.serialize(ticket(ticketId: 'AIO-1', title: 'One')));

    await service.reconstruct(tempDir.path);

    verify(() => embeddingProvider.embed(any())).called(1);
    verify(() => repository.updateEmbedding(any(), any())).called(1);
  });
}
