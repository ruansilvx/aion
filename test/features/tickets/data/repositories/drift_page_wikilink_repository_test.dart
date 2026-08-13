// test/features/tickets/data/repositories/drift_page_wikilink_repository_test.dart — DriftPageWikilinkRepository delegation tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/daos/page_wikilink_dao.dart';
import 'package:aion/features/tickets/data/repositories/drift_page_wikilink_repository.dart';
import 'package:aion/features/tickets/domain/entities/page_wikilink.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockPageWikilinkDao extends Mock implements PageWikilinkDao {}

/// [DriftPageWikilinkRepository] is a thin delegate over [PageWikilinkDao]
/// — per `project.md`'s repository-test convention, these tests mock the
/// DAO via mocktail rather than spinning up a real drift instance. See
/// `page_wikilink_dao_test.dart` for the DAO's own persistence-behavior
/// coverage.
void main() {
  late MockAppDatabase database;
  late MockPageWikilinkDao dao;
  late DriftPageWikilinkRepository repository;

  final row = PageWikilinkData(
    id: 'link-1',
    sourcePageId: 'page-a',
    targetPageId: 'page-b',
    createdAt: DateTime.utc(2026, 8, 13),
  );

  setUp(() {
    database = MockAppDatabase();
    dao = MockPageWikilinkDao();
    when(() => database.pageWikilinkDao).thenReturn(dao);
    repository = DriftPageWikilinkRepository(database);
  });

  group('getIncomingLinks', () {
    test('maps the DAO\'s rows to PageWikilink entities', () async {
      when(() => dao.getIncomingLinks('page-b')).thenAnswer((_) async => [row]);

      final result = await repository.getIncomingLinks('page-b');

      expect(result, [
        PageWikilink(
          id: 'link-1',
          sourcePageId: 'page-a',
          targetPageId: 'page-b',
          createdAt: row.createdAt,
        ),
      ]);
    });
  });

  group('getOutgoingLinks', () {
    test('maps the DAO\'s rows to PageWikilink entities', () async {
      when(() => dao.getOutgoingLinks('page-a')).thenAnswer((_) async => [row]);

      final result = await repository.getOutgoingLinks('page-a');

      expect(result.single.sourcePageId, 'page-a');
      expect(result.single.targetPageId, 'page-b');
    });
  });

  group('replaceOutgoingLinks', () {
    test('delegates to PageWikilinkDao.replaceOutgoingLinks', () async {
      when(
        () => dao.replaceOutgoingLinks('page-a', {'page-b', 'page-c'}),
      ).thenAnswer((_) async {});

      await repository.replaceOutgoingLinks('page-a', {'page-b', 'page-c'});

      verify(
        () => dao.replaceOutgoingLinks('page-a', {'page-b', 'page-c'}),
      ).called(1);
    });
  });

  group('deleteLinksForTickets', () {
    test('delegates to PageWikilinkDao.deleteLinksForTickets', () async {
      when(() => dao.deleteLinksForTickets(['a', 'b'])).thenAnswer((_) async {});

      await repository.deleteLinksForTickets(['a', 'b']);

      verify(() => dao.deleteLinksForTickets(['a', 'b'])).called(1);
    });
  });
}
