// test/features/tickets/data/repositories/drift_ticket_link_repository_test.dart — DriftTicketLinkRepository delegation tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/daos/ticket_link_dao.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_link_repository.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockTicketLinkDao extends Mock implements TicketLinkDao {}

/// [DriftTicketLinkRepository] is a thin delegate over [TicketLinkDao] —
/// per `project.md`'s repository-test convention, these tests mock the
/// DAO via mocktail rather than spinning up a real drift instance. See
/// `ticket_link_dao_test.dart` for the DAO's own persistence-behavior
/// coverage.
void main() {
  late MockAppDatabase database;
  late MockTicketLinkDao dao;
  late DriftTicketLinkRepository repository;

  final row = TicketLinkData(
    id: 'link-1',
    sourceTicketId: 'a',
    targetTicketId: 'b',
    linkType: TicketLinkType.relatesTo.name,
  );

  setUp(() {
    database = MockAppDatabase();
    dao = MockTicketLinkDao();
    when(() => database.ticketLinkDao).thenReturn(dao);
    repository = DriftTicketLinkRepository(database);
  });

  group('getLinkById', () {
    test('returns the row the DAO resolves', () async {
      when(() => dao.getLinkById('link-1')).thenAnswer((_) async => row);

      final result = await repository.getLinkById('link-1');

      expect(result, row);
    });

    test('returns null when the DAO resolves null', () async {
      when(() => dao.getLinkById('missing')).thenAnswer((_) async => null);

      final result = await repository.getLinkById('missing');

      expect(result, isNull);
    });
  });

  group('deleteLink', () {
    test('delegates to TicketLinkDao.deleteLink', () async {
      when(() => dao.deleteLink('link-1')).thenAnswer((_) async {});

      await repository.deleteLink('link-1');

      verify(() => dao.deleteLink('link-1')).called(1);
    });
  });

  group('updateLinkType', () {
    test('delegates to TicketLinkDao.updateLinkType with the new type', () async {
      when(
        () => dao.updateLinkType('link-1', TicketLinkType.blocks),
      ).thenAnswer((_) async {});

      await repository.updateLinkType('link-1', TicketLinkType.blocks);

      verify(
        () => dao.updateLinkType('link-1', TicketLinkType.blocks),
      ).called(1);
    });
  });
}
