import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/tickets/data/services/document_parent_migration_service.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockTicketLinkRepository extends Mock implements TicketLinkRepository {}

void main() {
  late MockTicketRepository ticketRepository;
  late MockTicketLinkRepository linkRepository;

  Ticket build({
    required String id,
    required TicketType type,
    String? parentId,
  }) => Ticket(
    id: id,
    ticketId: 'AIO-$id',
    type: type,
    title: 'Ticket $id',
    status: TicketStatus.backlog,
    parentId: parentId,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUpAll(() {
    registerFallbackValue(TicketLinkType.relatesTo);
  });

  setUp(() {
    ticketRepository = MockTicketRepository();
    linkRepository = MockTicketLinkRepository();
    when(
      () => ticketRepository.updateTicketParent(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => linkRepository.createLink(
        sourceTicketId: any(named: 'sourceTicketId'),
        targetTicketId: any(named: 'targetTicketId'),
        linkType: any(named: 'linkType'),
      ),
    ).thenAnswer((_) async {});
  });

  Future<DocumentParentMigrationService> buildService() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return DocumentParentMigrationService(
      ticketRepository,
      linkRepository,
      prefs,
    );
  }

  test(
    'converts a resource/page parented under a work item into a link and clears parentId',
    () async {
      final epic = build(id: 'epic-1', type: TicketType.epic);
      final page = build(id: 'page-1', type: TicketType.page, parentId: epic.id);
      when(
        () => ticketRepository.getAllTickets(),
      ).thenAnswer((_) async => [epic, page]);

      final service = await buildService();
      await service.migrateIfNeeded();

      verify(
        () => linkRepository.createLink(
          sourceTicketId: page.id,
          targetTicketId: epic.id,
          linkType: TicketLinkType.relatesTo,
        ),
      ).called(1);
      verify(() => ticketRepository.updateTicketParent(page.id, null)).called(1);
    },
  );

  test('leaves unrelated tickets untouched', () async {
    final epic = build(id: 'epic-1', type: TicketType.epic);
    final task = build(id: 'task-1', type: TicketType.task, parentId: epic.id);
    final page = build(id: 'page-1', type: TicketType.page); // no parent
    when(
      () => ticketRepository.getAllTickets(),
    ).thenAnswer((_) async => [epic, task, page]);

    final service = await buildService();
    await service.migrateIfNeeded();

    verifyNever(
      () => linkRepository.createLink(
        sourceTicketId: any(named: 'sourceTicketId'),
        targetTicketId: any(named: 'targetTicketId'),
        linkType: any(named: 'linkType'),
      ),
    );
    verifyNever(() => ticketRepository.updateTicketParent(any(), any()));
  });

  test('does not touch a page already parented under another page', () async {
    final parentPage = build(id: 'page-1', type: TicketType.page);
    final childPage = build(
      id: 'page-2',
      type: TicketType.page,
      parentId: parentPage.id,
    );
    when(
      () => ticketRepository.getAllTickets(),
    ).thenAnswer((_) async => [parentPage, childPage]);

    final service = await buildService();
    await service.migrateIfNeeded();

    verifyNever(() => ticketRepository.updateTicketParent(any(), any()));
  });

  test('no-ops on a second call (flag gating)', () async {
    final epic = build(id: 'epic-1', type: TicketType.epic);
    final page = build(id: 'page-1', type: TicketType.page, parentId: epic.id);
    when(
      () => ticketRepository.getAllTickets(),
    ).thenAnswer((_) async => [epic, page]);

    final service = await buildService();
    await service.migrateIfNeeded();
    await service.migrateIfNeeded();

    verify(
      () => linkRepository.createLink(
        sourceTicketId: any(named: 'sourceTicketId'),
        targetTicketId: any(named: 'targetTicketId'),
        linkType: any(named: 'linkType'),
      ),
    ).called(1);
  });
}
