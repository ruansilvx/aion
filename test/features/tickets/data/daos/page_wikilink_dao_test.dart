// test/features/tickets/data/daos/page_wikilink_dao_test.dart — PageWikilinkDao persistence-behavior tests.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/tickets/data/daos/page_wikilink_dao.dart';

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

/// Direct [PageWikilinkDao] tests against a real in-memory drift
/// instance — per `flutter-conventions.md`'s stated exception (same
/// precedent as `ticket_link_dao_test.dart`), since
/// [PageWikilinkDao.replaceOutgoingLinks]'s delete-then-batch-insert
/// transaction shape is exactly the kind of thing a mocked DAO can't
/// catch a mistake in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late PageWikilinkDao dao;

  setUp(() {
    database = AppDatabase(_testProject, NativeDatabase.memory());
    dao = database.pageWikilinkDao;
  });

  tearDown(() async {
    await database.close();
  });

  group('getIncomingLinks / getOutgoingLinks', () {
    test('round-trips a row written via replaceOutgoingLinks', () async {
      await dao.replaceOutgoingLinks('page-a', {'page-b'});

      final incoming = await dao.getIncomingLinks('page-b');
      final outgoing = await dao.getOutgoingLinks('page-a');

      expect(incoming, hasLength(1));
      expect(incoming.single.sourcePageId, 'page-a');
      expect(incoming.single.targetPageId, 'page-b');
      expect(outgoing, hasLength(1));
      expect(outgoing.single.targetPageId, 'page-b');
    });

    test('getIncomingLinks returns empty for a target with no referrers', () async {
      final incoming = await dao.getIncomingLinks('page-nobody-links-to');

      expect(incoming, isEmpty);
    });

    test('getOutgoingLinks returns empty for a source with no outgoing links', () async {
      final outgoing = await dao.getOutgoingLinks('page-with-nothing');

      expect(outgoing, isEmpty);
    });
  });

  group('replaceOutgoingLinks', () {
    test('clears prior rows and inserts the new set', () async {
      await dao.replaceOutgoingLinks('page-a', {'page-b', 'page-c'});

      await dao.replaceOutgoingLinks('page-a', {'page-d'});

      final outgoing = await dao.getOutgoingLinks('page-a');
      expect(outgoing.map((r) => r.targetPageId), ['page-d']);
    });

    test('an empty target set clears all outgoing rows', () async {
      await dao.replaceOutgoingLinks('page-a', {'page-b', 'page-c'});

      await dao.replaceOutgoingLinks('page-a', {});

      expect(await dao.getOutgoingLinks('page-a'), isEmpty);
    });

    test('does not disturb another source page\'s outgoing rows', () async {
      await dao.replaceOutgoingLinks('page-a', {'page-x'});
      await dao.replaceOutgoingLinks('page-b', {'page-y'});

      await dao.replaceOutgoingLinks('page-a', {});

      expect(await dao.getOutgoingLinks('page-a'), isEmpty);
      expect(await dao.getOutgoingLinks('page-b'), hasLength(1));
    });
  });

  group('deleteLinksForTickets', () {
    test('removes rows matching a source id', () async {
      await dao.replaceOutgoingLinks('page-a', {'page-b'});

      await dao.deleteLinksForTickets(['page-a']);

      expect(await dao.getOutgoingLinks('page-a'), isEmpty);
      expect(await dao.getIncomingLinks('page-b'), isEmpty);
    });

    test('removes rows matching a target id', () async {
      await dao.replaceOutgoingLinks('page-a', {'page-b'});

      await dao.deleteLinksForTickets(['page-b']);

      expect(await dao.getOutgoingLinks('page-a'), isEmpty);
    });

    test('removes rows matching either side in one call', () async {
      await dao.replaceOutgoingLinks('page-a', {'page-b'});
      await dao.replaceOutgoingLinks('page-c', {'page-d'});

      await dao.deleteLinksForTickets(['page-b', 'page-c']);

      expect(await dao.getOutgoingLinks('page-a'), isEmpty);
      expect(await dao.getOutgoingLinks('page-c'), isEmpty);
    });
  });
}
