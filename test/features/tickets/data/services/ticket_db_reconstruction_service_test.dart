import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_repository.dart';
import 'package:aion/features/tickets/data/services/ticket_db_reconstruction_service.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockEmbeddingProvider extends Mock implements EmbeddingProvider {}

class _NullEmbeddingProvider implements EmbeddingProvider {
  @override
  Future<Uint8List> embed(String text) async => Uint8List(0);
}

/// Dummy project for [AppDatabase] — unused here since every test in the
/// real-repository group passes an explicit in-memory executor. Mirrors
/// `drift_ticket_repository_test.dart`'s identical fixture.
final _testProject = Project(
  id: 'test-project',
  name: 'Test Project',
  storageKey: 'test-project',
  baselineVersion: '0.1.0',
  createdAt: DateTime(2024, 1, 1),
  lastOpenedAt: DateTime(2024, 1, 1),
);

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
        status: 'backlog',
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
    when(() => repository.importTicket(any())).thenAnswer((_) async {});
    when(
      () => repository.getTrashedTickets(),
    ).thenAnswer((_) async => []);
    when(() => repository.updateEmbedding(any(), any())).thenAnswer((_) async {});
    when(() => embeddingProvider.embed(any())).thenAnswer(
      (_) async => Uint8List.fromList([9, 9, 9]),
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Ticket ticket({
    required String ticketId,
    required String title,
    DateTime? deletedAt,
  }) => Ticket(
    id: 'internal-$ticketId',
    ticketId: ticketId,
    type: TicketType.resource,
    title: title,
    description: 'Body for $ticketId.',
    status: 'backlog',
    createdAt: DateTime.utc(2026, 7, 18),
    updatedAt: DateTime.utc(2026, 7, 18),
    deletedAt: deletedAt,
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
    verify(() => repository.importTicket(any())).called(2);
    verifyNever(() => repository.createTicket(any()));
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

  test(
    'two files sharing a ticketId: the first imports, the second updates '
    'the same row instead of a second import',
    () async {
      when(() => repository.getAllTickets()).thenAnswer((_) async => []);
      await File('${tempDir.path}/tickets/AIO-1.md').writeAsString(
        serializer.serialize(ticket(ticketId: 'AIO-1', title: 'First file')),
      );
      await File('${tempDir.path}/tickets/AIO-1-dup.md').writeAsString(
        serializer.serialize(ticket(ticketId: 'AIO-1', title: 'Second file')),
      );

      final report = await service.reconstruct(tempDir.path);

      expect(report.importedCount, 2);
      expect(report.skippedPaths, isEmpty);
      verify(() => repository.importTicket(any())).called(1);
      verify(() => repository.updateTicket(any())).called(1);
    },
  );

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

  test('reconstructs a new ticket with its deletedAt from the file', () async {
    when(() => repository.getAllTickets()).thenAnswer((_) async => []);
    final trashedAt = DateTime.utc(2026, 8, 1);
    await File('${tempDir.path}/tickets/AIO-1.md').writeAsString(
      serializer.serialize(
        ticket(ticketId: 'AIO-1', title: 'One', deletedAt: trashedAt),
      ),
    );

    await service.reconstruct(tempDir.path);

    final captured = verify(
      () => repository.importTicket(captureAny()),
    ).captured;
    final imported = captured.single as Ticket;
    expect(imported.deletedAt, trashedAt);
  });

  test(
    'updating an existing row from a file with deletedAt overwrites the '
    'row\'s previous value',
    () async {
      final existing = ticket(ticketId: 'AIO-1', title: 'Old title');
      when(
        () => repository.getAllTickets(),
      ).thenAnswer((_) async => [existing]);
      // The file's deletedAt (non-null) disagrees with existing's
      // (null) — reconstruct() must reconcile this via trashTicket, not
      // by leaning on updateTicket (which never touches deletedAt on a
      // real DriftTicketRepository — see the real-repository group
      // below for the integration-level proof of that).
      final trashedAt = DateTime.utc(2026, 8, 1);
      when(
        () => repository.trashTicket(existing.id),
      ).thenAnswer((_) async => [existing.id]);
      when(() => repository.getTicketById(existing.id)).thenAnswer(
        (_) async =>
            ticket(ticketId: 'AIO-1', title: 'Old title', deletedAt: trashedAt),
      );
      await File('${tempDir.path}/tickets/AIO-1.md').writeAsString(
        serializer.serialize(
          ticket(ticketId: 'AIO-1', title: 'Old title', deletedAt: trashedAt),
        ),
      );

      await service.reconstruct(tempDir.path);

      verify(() => repository.trashTicket(existing.id)).called(1);
      final captured = verify(
        () => repository.updateTicket(captureAny()),
      ).captured;
      final updated = captured.single as Ticket;
      expect(updated.id, existing.id);
      expect(updated.deletedAt, trashedAt);
    },
  );

  test('bulk-backfills embeddings only for imported tickets lacking one', () async {
    when(() => repository.getAllTickets()).thenAnswer((_) async => []);
    await File('${tempDir.path}/tickets/AIO-1.md')
        .writeAsString(serializer.serialize(ticket(ticketId: 'AIO-1', title: 'One')));

    await service.reconstruct(tempDir.path);

    verify(() => embeddingProvider.embed(any())).called(1);
    verify(() => repository.updateEmbedding(any(), any())).called(1);
  });

  // The tests above all use a mocked TicketRepository — sufficient to
  // assert *what Ticket object* reconstruct() passes downstream, but not
  // that a real DriftTicketRepository actually persists it (see
  // fix-ticket-trash-cascade-projection-gap's proposal.md: this exact gap
  // — a mock-only test proving nothing about real DB persistence — is
  // what let the underlying deletedAt round-trip bug ship unnoticed).
  // These use a real DriftTicketRepository over an in-memory database
  // instead.
  group('reconstruct against a real DriftTicketRepository '
      '(trash-state integration)', () {
    late AppDatabase database;
    late DriftTicketRepository realRepository;
    late TicketDbReconstructionService realService;
    late Directory realTempDir;

    setUp(() async {
      database = AppDatabase(_testProject, NativeDatabase.memory());
      realRepository = DriftTicketRepository(database);
      realService = TicketDbReconstructionService(
        realRepository,
        serializer,
        _NullEmbeddingProvider(),
      );
      realTempDir = await Directory.systemTemp.createTemp(
        'ticket_db_reconstruction_real_test',
      );
      await Directory('${realTempDir.path}/tickets').create(recursive: true);
    });

    tearDown(() async {
      await database.close();
      await realTempDir.delete(recursive: true);
    });

    test(
      'does not throw on a ticket that is genuinely trashed in the DB '
      'whose .md file still exists on disk, and leaves it trashed',
      () async {
        final now = DateTime.utc(2026, 9, 8);
        await realRepository.importTicket(
          Ticket(
            id: 'internal-1',
            ticketId: 'AIO-1',
            type: TicketType.epic,
            title: 'Duplicate epic',
            status: 'backlog',
            createdAt: now,
            updatedAt: now,
          ),
        );
        final live = (await realRepository.getAllTickets()).single;
        await realRepository.trashTicket(live.id);
        await File('${realTempDir.path}/tickets/AIO-1.md').writeAsString(
          serializer.serialize(
            Ticket(
              id: live.id,
              ticketId: live.ticketId,
              type: live.type,
              title: live.title,
              status: live.status,
              createdAt: live.createdAt,
              updatedAt: live.updatedAt,
              deletedAt: DateTime.utc(2026, 9, 8, 22, 42),
            ),
          ),
        );

        await expectLater(
          realService.reconstruct(realTempDir.path),
          completes,
        );

        final trashed = await realRepository.getTrashedTickets();
        expect(trashed, hasLength(1));
        expect(trashed.single.ticketId, 'AIO-1');
        expect(await realRepository.getAllTickets(), isEmpty);
      },
    );

    test(
      'reconciles a live DB row whose .md file says trashed by actually '
      'calling trashTicket — not just passing updateTicket a Ticket '
      'object with deletedAt set, which real DriftTicketRepository.'
      'updateTicket silently ignores',
      () async {
        final now = DateTime.utc(2026, 9, 8);
        await realRepository.importTicket(
          Ticket(
            id: 'internal-2',
            ticketId: 'AIO-2',
            type: TicketType.epic,
            title: 'Live in DB, trashed on disk',
            status: 'backlog',
            createdAt: now,
            updatedAt: now,
          ),
        );
        final live = (await realRepository.getAllTickets()).single;
        await File('${realTempDir.path}/tickets/AIO-2.md').writeAsString(
          serializer.serialize(
            Ticket(
              id: live.id,
              ticketId: live.ticketId,
              type: live.type,
              title: live.title,
              status: live.status,
              createdAt: live.createdAt,
              updatedAt: live.updatedAt,
              deletedAt: DateTime.utc(2026, 9, 8, 22, 42),
            ),
          ),
        );

        await realService.reconstruct(realTempDir.path);

        final row = await realRepository.getTicketById(live.id);
        expect(row!.deletedAt, isNotNull);
        expect(await realRepository.getTrashedTickets(), hasLength(1));
      },
    );

    test(
      "/verify regression — a descendant cascade-trashed by its parent's "
      'own reconciliation does not also trigger a second, redundant '
      'trashTicket call from its own (otherwise-stale) reconciliation '
      'later in the same reconstruct() pass',
      () async {
        // A spy wrapping the real repository: mocktail tracks call counts
        // precisely, while every call still executes against the real,
        // in-memory database — the only way to observe whether
        // reconstruct()'s in-memory existingByTicketId snapshot was
        // refreshed after a cascade, since a real DriftTicketRepository
        // has no call-count introspection of its own.
        final spyRepository = MockTicketRepository();
        when(
          () => spyRepository.getAllTickets(),
        ).thenAnswer((_) => realRepository.getAllTickets());
        when(
          () => spyRepository.getTrashedTickets(),
        ).thenAnswer((_) => realRepository.getTrashedTickets());
        when(() => spyRepository.getTicketById(any())).thenAnswer(
          (i) => realRepository.getTicketById(i.positionalArguments[0] as String),
        );
        when(() => spyRepository.updateTicket(any())).thenAnswer(
          (i) => realRepository.updateTicket(i.positionalArguments[0] as Ticket),
        );
        when(() => spyRepository.importTicket(any())).thenAnswer(
          (i) => realRepository.importTicket(i.positionalArguments[0] as Ticket),
        );
        when(() => spyRepository.trashTicket(any())).thenAnswer(
          (i) => realRepository.trashTicket(i.positionalArguments[0] as String),
        );
        when(
          () => spyRepository.updateEmbedding(any(), any()),
        ).thenAnswer((_) async {});
        final spyService = TicketDbReconstructionService(
          spyRepository,
          serializer,
          _NullEmbeddingProvider(),
        );

        final now = DateTime.utc(2026, 9, 8);
        await realRepository.importTicket(
          Ticket(
            id: 'internal-epic',
            ticketId: 'AIO-3',
            type: TicketType.epic,
            title: 'Epic',
            status: 'backlog',
            createdAt: now,
            updatedAt: now,
          ),
        );
        final epic = (await realRepository.getAllTickets()).single;
        await realRepository.importTicket(
          Ticket(
            id: 'internal-child',
            ticketId: 'AIO-4',
            type: TicketType.task,
            title: 'Child',
            status: 'backlog',
            parentId: epic.id,
            createdAt: now,
            updatedAt: now,
          ),
        );
        final child = (await realRepository.getTicketById('internal-child'))!;

        // Both files agree the whole subtree should be trashed — a
        // consistent cascade, not a genuine conflict (see
        // _reconcileTrashState's own dartdoc for why a *genuine*
        // conflict can't be fully resolved either way).
        final trashedAt = DateTime.utc(2026, 9, 8, 22, 42);
        Future<void> writeFile(Ticket t) => File(
          '${realTempDir.path}/tickets/${t.ticketId}.md',
        ).writeAsString(
          serializer.serialize(
            Ticket(
              id: t.id,
              ticketId: t.ticketId,
              type: t.type,
              title: t.title,
              status: t.status,
              parentId: t.parentId,
              createdAt: t.createdAt,
              updatedAt: t.updatedAt,
              deletedAt: trashedAt,
            ),
          ),
        );
        await writeFile(epic);
        await writeFile(child);

        await spyService.reconstruct(realTempDir.path);

        // Whichever of the two files reconstruct() happens to process
        // first, its own reconciliation cascades and trashes both —
        // the *other* file's reconciliation must then see that cascade
        // (via the refreshed cache) and recognize its own ticket
        // already matches, rather than firing its own redundant
        // trashTicket call.
        verify(() => spyRepository.trashTicket(any())).called(1);
        expect(await realRepository.getTrashedTickets(), hasLength(2));
      },
    );
  });
}
