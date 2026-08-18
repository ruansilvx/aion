import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/markdown/ticket_markdown_serializer.dart';
import 'package:aion/features/tickets/data/services/ticket_parent_trash_service.dart';
import 'package:aion/features/tickets/data/services/ticket_repair_service.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockTicketParentTrashService extends Mock
    implements TicketParentTrashService {}

void main() {
  late MockTicketRepository repository;
  late MockTicketParentTrashService parentTrashService;
  late TicketMarkdownSerializer serializer;
  late TicketRepairService repairService;
  late Directory tempDir;

  final ticket = Ticket(
    id: 'internal-1',
    ticketId: 'AIO-42',
    type: TicketType.resource,
    title: 'Original title',
    description: 'Original description.',
    status: TicketStatus.backlog,
    createdAt: DateTime.utc(2026, 7, 18),
    updatedAt: DateTime.utc(2026, 7, 18),
  );

  setUpAll(() {
    registerFallbackValue(ticket);
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue(TicketSyncStatus.synced);
  });

  setUp(() async {
    repository = MockTicketRepository();
    parentTrashService = MockTicketParentTrashService();
    serializer = TicketMarkdownSerializer();
    repairService = TicketRepairService(repository, serializer, parentTrashService);
    tempDir = await Directory.systemTemp.createTemp('ticket_repair_service_test');
    await Directory('${tempDir.path}/tickets').create(recursive: true);

    when(() => repository.getAllTickets()).thenAnswer((_) async => [ticket]);
    when(() => repository.updateSyncStatus(any(), any())).thenAnswer((_) async {});
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<void> writeFile(String content) {
    return File('${tempDir.path}/tickets/AIO-42.md').writeAsString(content);
  }

  group('reformat', () {
    test('returns false when the file does not exist', () async {
      final ok = await repairService.reformat('AIO-42', tempDir.path);

      expect(ok, isFalse);
      verifyNever(() => repository.updateSyncStatus(any(), any()));
    });

    test(
      'returns false when the content is still Unparseable after trimming',
      () async {
        await writeFile('this is not valid frontmatter at all   \n');

        final ok = await repairService.reformat('AIO-42', tempDir.path);

        expect(ok, isFalse);
        verifyNever(() => repository.updateSyncStatus(any(), any()));
        verifyNever(
          () => parentTrashService.applyFromParsedFields(any(), any()),
        );
      },
    );

    test(
      'trims, re-validates parentId/deletedAt, writes the file, and marks '
      'synced when there is no relevant transition',
      () async {
        when(
          () => parentTrashService.applyFromParsedFields(any(), any()),
        ).thenAnswer((_) async => true);
        final withTrailingWhitespace = '${serializer.serialize(ticket)}   \n';
        await writeFile(withTrailingWhitespace);

        final ok = await repairService.reformat('AIO-42', tempDir.path);

        expect(ok, isTrue);
        verify(
          () => parentTrashService.applyFromParsedFields(ticket, any()),
        ).called(1);
        verify(
          () => repository.updateSyncStatus(ticket.id, TicketSyncStatus.synced),
        ).called(1);
        final written = await File(
          '${tempDir.path}/tickets/AIO-42.md',
        ).readAsString();
        expect(written.contains('   \n'), isFalse);
      },
    );

    test(
      'returns false and does not touch the file/DB when '
      'TicketParentTrashService rejects the reformatted parentId/deletedAt',
      () async {
        when(
          () => parentTrashService.applyFromParsedFields(any(), any()),
        ).thenAnswer((_) async => false);
        final original = '${serializer.serialize(ticket)}   \n';
        await writeFile(original);

        final ok = await repairService.reformat('AIO-42', tempDir.path);

        expect(ok, isFalse);
        verify(
          () => parentTrashService.applyFromParsedFields(ticket, any()),
        ).called(1);
        verifyNever(() => repository.updateSyncStatus(any(), any()));
        final onDisk = await File(
          '${tempDir.path}/tickets/AIO-42.md',
        ).readAsString();
        expect(onDisk, original); // untouched — not overwritten
      },
    );
  });

  group('restoreFromLastKnownGood', () {
    test(
      'overwrites the file with the current DB row and marks synced',
      () async {
        await writeFile('stale or corrupted content');

        await repairService.restoreFromLastKnownGood('AIO-42', tempDir.path);

        final written = await File(
          '${tempDir.path}/tickets/AIO-42.md',
        ).readAsString();
        expect(written, serializer.serialize(ticket));
        verify(
          () => repository.updateSyncStatus(ticket.id, TicketSyncStatus.synced),
        ).called(1);
      },
    );

    test('no-ops when the ticket is unknown (deleted)', () async {
      when(() => repository.getAllTickets()).thenAnswer((_) async => []);
      await writeFile('anything');

      await repairService.restoreFromLastKnownGood('AIO-42', tempDir.path);

      verifyNever(() => repository.updateSyncStatus(any(), any()));
    });
  });
}
