// test/features/tickets/data/daos/ticket_link_dao_test.dart — TicketLinkDao.getLinkById/deleteLink/updateLinkType tests.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/tickets/data/daos/ticket_link_dao.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';

/// Dummy project [AppDatabase] now requires per-project addressing —
/// unused here since every test passes an explicit in-memory executor.
final _testProject = Project(
  id: 'test-project',
  name: 'Test Project',
  storageKey: 'test-project',
  baselineVersion: '0.1.0',
  createdAt: DateTime(2024, 1, 1),
  lastOpenedAt: DateTime(2024, 1, 1),
);

/// Direct [TicketLinkDao] tests against a real in-memory drift instance —
/// per `flutter-conventions.md`'s stated exception, whether
/// [TicketLinkDao.updateLinkType]'s `UPDATE` genuinely touches only the
/// `link_type` column (and not `source_ticket_id`/`target_ticket_id`) is
/// exactly the kind of thing a mocked DAO can't catch a mistake in, so
/// this isn't mocked like `DriftTicketLinkRepository`'s own delegation
/// tests are.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late TicketLinkDao dao;

  setUp(() {
    database = AppDatabase(_testProject, NativeDatabase.memory());
    dao = database.ticketLinkDao;
  });

  tearDown(() async {
    await database.close();
  });

  Future<String> insertLink({
    String id = 'link-1',
    String sourceTicketId = 'a',
    String targetTicketId = 'b',
    TicketLinkType linkType = TicketLinkType.relatesTo,
  }) async {
    await dao.insertLink(
      TicketLinksTableCompanion.insert(
        id: id,
        sourceTicketId: sourceTicketId,
        targetTicketId: targetTicketId,
        linkType: linkType.name,
      ),
    );
    return id;
  }

  group('getLinkById', () {
    test('returns the row with a matching id', () async {
      await insertLink(id: 'link-1', linkType: TicketLinkType.blocks);

      final row = await dao.getLinkById('link-1');

      expect(row, isNotNull);
      expect(row!.sourceTicketId, 'a');
      expect(row.targetTicketId, 'b');
      expect(row.linkType, TicketLinkType.blocks.name);
    });

    test('returns null for an id that does not exist', () async {
      final row = await dao.getLinkById('missing');

      expect(row, isNull);
    });
  });

  group('deleteLink', () {
    test('removes exactly the row with the given id', () async {
      await insertLink(id: 'link-1');
      await insertLink(id: 'link-2', sourceTicketId: 'c', targetTicketId: 'd');

      await dao.deleteLink('link-1');

      expect(await dao.getLinkById('link-1'), isNull);
      expect(await dao.getLinkById('link-2'), isNotNull);
    });

    test('no-ops for an id that does not exist', () async {
      await insertLink(id: 'link-1');

      await dao.deleteLink('missing');

      expect(await dao.getLinkById('link-1'), isNotNull);
    });
  });

  group('updateLinkType', () {
    test('changes only linkType, leaves source/target ids untouched', () async {
      await insertLink(
        id: 'link-1',
        sourceTicketId: 'a',
        targetTicketId: 'b',
        linkType: TicketLinkType.relatesTo,
      );

      await dao.updateLinkType('link-1', TicketLinkType.blocks);

      final row = await dao.getLinkById('link-1');
      expect(row!.linkType, TicketLinkType.blocks.name);
      expect(row.sourceTicketId, 'a');
      expect(row.targetTicketId, 'b');
    });

    test('no-ops for an id that does not exist', () async {
      await insertLink(id: 'link-1', linkType: TicketLinkType.relatesTo);

      await dao.updateLinkType('missing', TicketLinkType.blocks);

      final row = await dao.getLinkById('link-1');
      expect(row!.linkType, TicketLinkType.relatesTo.name);
    });
  });
}
