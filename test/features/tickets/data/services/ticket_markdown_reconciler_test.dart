import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/core/markdown/ticket_markdown_serializer.dart';
import 'package:aion/features/tickets/data/services/active_ticket_view_registry.dart';
import 'package:aion/features/tickets/data/services/ticket_markdown_reconciler.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockEmbeddingProvider extends Mock implements EmbeddingProvider {}

void main() {
  late MockTicketRepository repository;
  late MockEmbeddingProvider embeddingProvider;
  late ActiveTicketViewRegistry registry;
  late TicketMarkdownReconciler reconciler;
  late Directory tempDir;

  final resourceTicket = Ticket(
    id: 'internal-1',
    ticketId: 'AIO-42',
    type: TicketType.resource,
    title: 'Original title',
    description: 'Original description.',
    status: TicketStatus.backlog,
    createdAt: DateTime.utc(2026, 7, 18),
    updatedAt: DateTime.utc(2026, 7, 18),
  );

  final workItemTicket = resourceTicket.copyWith(type: TicketType.task);

  setUpAll(() {
    registerFallbackValue(TicketSyncStatus.synced);
    registerFallbackValue(TicketStatus.backlog);
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
    registry = ActiveTicketViewRegistry();
    reconciler = TicketMarkdownReconciler(
      repository,
      TicketMarkdownSerializer(),
      registry,
      embeddingProvider,
    );
    tempDir = await Directory.systemTemp.createTemp(
      'ticket_markdown_reconciler_test',
    );
    await Directory('${tempDir.path}/tickets').create(recursive: true);

    when(() => repository.updateSyncStatus(any(), any())).thenAnswer((_) async {});
    when(() => repository.updateTicket(any())).thenAnswer((_) async {});
    when(() => repository.updateTicketStatus(any(), any())).thenAnswer((_) async {});
    when(() => repository.updateEmbedding(any(), any())).thenAnswer((_) async {});
    when(() => embeddingProvider.embed(any())).thenAnswer(
      (_) async => Uint8List.fromList([1, 2, 3]),
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<void> writeFile(String content) {
    return File('${tempDir.path}/tickets/AIO-42.md').writeAsString(content);
  }

  test('no-ops for a non-resource/page ticket type', () async {
    when(() => repository.getAllTickets()).thenAnswer((_) async => [workItemTicket]);
    await writeFile('not valid frontmatter');

    await reconciler.reconcile('AIO-42', tempDir.path);

    verifyNever(() => repository.updateSyncStatus(any(), any()));
  });

  test('no-ops when the ticket is unknown (deleted)', () async {
    when(() => repository.getAllTickets()).thenAnswer((_) async => []);
    await writeFile('anything');

    await reconciler.reconcile('AIO-42', tempDir.path);

    verifyNever(() => repository.updateSyncStatus(any(), any()));
  });

  group('Unparseable', () {
    test('sets needsRepair and does not touch content', () async {
      when(() => repository.getAllTickets()).thenAnswer((_) async => [resourceTicket]);
      await writeFile('this is not valid frontmatter at all');

      await reconciler.reconcile('AIO-42', tempDir.path);

      verify(
        () => repository.updateSyncStatus(
          resourceTicket.id,
          TicketSyncStatus.needsRepair,
        ),
      ).called(1);
      verifyNever(() => repository.updateTicket(any()));
    });
  });

  group('ParsedOk — background apply (not actively viewed)', () {
    test('applies fields and cycles pendingReconcile -> synced', () async {
      when(() => repository.getAllTickets()).thenAnswer((_) async => [resourceTicket]);
      final serializer = TicketMarkdownSerializer();
      await writeFile(
        serializer.serialize(
          resourceTicket.copyWith(
            title: 'Edited externally',
            description: () => 'Edited body.',
          ),
        ),
      );

      await reconciler.reconcile('AIO-42', tempDir.path);

      verify(
        () => repository.updateSyncStatus(
          resourceTicket.id,
          TicketSyncStatus.pendingReconcile,
        ),
      ).called(1);
      verify(
        () => repository.updateSyncStatus(
          resourceTicket.id,
          TicketSyncStatus.synced,
        ),
      ).called(1);
      final captured = verify(() => repository.updateTicket(captureAny())).captured;
      final updated = captured.single as Ticket;
      expect(updated.title, 'Edited externally');
      expect(updated.description, 'Edited body.');
    });

    test('triggers embedding regen when title/description changed', () async {
      when(() => repository.getAllTickets()).thenAnswer((_) async => [resourceTicket]);
      final serializer = TicketMarkdownSerializer();
      await writeFile(
        serializer.serialize(resourceTicket.copyWith(title: 'New title')),
      );

      await reconciler.reconcile('AIO-42', tempDir.path);
      // The embedding trigger is fire-and-forget (unawaited) — pump the
      // microtask queue so it has a chance to run before asserting.
      await Future<void>.delayed(Duration.zero);

      verify(() => embeddingProvider.embed(any())).called(1);
      verify(() => repository.updateEmbedding(resourceTicket.id, any())).called(1);
    });
  });

  group('ParsedPartial', () {
    test('applies valid fields, keeps DB value for the invalid one', () async {
      when(() => repository.getAllTickets()).thenAnswer((_) async => [resourceTicket]);
      final serializer = TicketMarkdownSerializer();
      final content = serializer
          .serialize(resourceTicket)
          .replaceFirst('status: backlog', 'status: not-a-status');
      await writeFile(content);

      await reconciler.reconcile('AIO-42', tempDir.path);

      // Partial success stays synced — never flagged needsRepair.
      verifyNever(
        () => repository.updateSyncStatus(any(), TicketSyncStatus.needsRepair),
      );
      verify(
        () => repository.updateSyncStatus(
          resourceTicket.id,
          TicketSyncStatus.synced,
        ),
      ).called(1);
      // status field was invalid, so updateTicketStatus must not fire.
      verifyNever(() => repository.updateTicketStatus(any(), any()));
    });
  });

  group('active-view blocking', () {
    test('defers apply while the ticket is actively viewed, then applies', () async {
      when(() => repository.getAllTickets()).thenAnswer((_) async => [resourceTicket]);
      final serializer = TicketMarkdownSerializer();
      await writeFile(
        serializer.serialize(resourceTicket.copyWith(title: 'Edited while viewing')),
      );
      registry.activeTicketId.value = 'AIO-42';

      await reconciler.reconcile('AIO-42', tempDir.path);
      // Deferred — nothing applied yet while still the active view.
      verifyNever(() => repository.updateTicket(any()));

      registry.activeTicketId.value = null;
      // The deferred re-reconcile does real file I/O (not just
      // microtasks), so a zero-duration delay isn't reliably enough to
      // let it finish before asserting.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final captured = verify(() => repository.updateTicket(captureAny())).captured;
      expect((captured.single as Ticket).title, 'Edited while viewing');
    });
  });
}
