// test/core/automation/data/decision_log_dao_test.dart — DecisionLogDao tests.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/projects.dart';

/// Dummy project — every test passes an explicit in-memory executor,
/// mirroring `ticket_dao_test.dart`'s own precedent.
final _testProject = Project(
  id: 'test-project',
  name: 'Test Project',
  storageKey: 'test-project',
  baselineVersion: '0.1.0',
  createdAt: DateTime(2024, 1, 1),
  lastOpenedAt: DateTime(2024, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DecisionLogService', () {
    test('record() inserts a decision-log entry with all fields', () async {
      final database = AppDatabase(_testProject, NativeDatabase.memory());
      addTearDown(database.close);

      final service = DecisionLogService(database);
      final createdAt = DateTime.now().millisecondsSinceEpoch;
      await service.record(
        ticketId: 'ticket-1',
        source: 'sddStage',
        sourceDetail: 'applied-context',
        confidence: 'auto',
        outcome: 'proceed',
        gateResult: 'fired',
        detail: 'test-detail',
      );

      final rows = await database.select(database.decisionLogTable).get();

      expect(rows, hasLength(1));
      expect(rows.first.ticketId, 'ticket-1');
      expect(rows.first.source, 'sddStage');
      expect(rows.first.sourceDetail, 'applied-context');
      expect(rows.first.confidence, 'auto');
      expect(rows.first.outcome, 'proceed');
      expect(rows.first.gateResult, 'fired');
      expect(rows.first.detail, 'test-detail');
      expect(
        rows.first.createdAt,
        greaterThanOrEqualTo(createdAt),
      );
    });

    test('record() accepts nullable fields', () async {
      final database = AppDatabase(_testProject, NativeDatabase.memory());
      addTearDown(database.close);

      final service = DecisionLogService(database);
      await service.record(
        ticketId: 'ticket-2',
        source: 'ideaPromotion',
        gateResult: 'pending',
      );

      final rows = await database.select(database.decisionLogTable).get();

      expect(rows, hasLength(1));
      expect(rows.first.ticketId, 'ticket-2');
      expect(rows.first.source, 'ideaPromotion');
      expect(rows.first.sourceDetail, isNull);
      expect(rows.first.confidence, isNull);
      expect(rows.first.outcome, isNull);
      expect(rows.first.gateResult, 'pending');
      expect(rows.first.detail, isNull);
    });

    test('record() swallows exceptions and never throws', () async {
      final database = AppDatabase(_testProject, NativeDatabase.memory());
      addTearDown(database.close);

      final service = DecisionLogService(database);

      // Close the database to force a DB error on the next write
      await database.close();

      // This should not throw even though the database is closed
      expect(
        () => service.record(
          ticketId: 'ticket-3',
          source: 'codingExecution',
          gateResult: 'confirmed',
        ),
        returnsNormally,
      );
    });

    test('record() generates a UUID id for each row', () async {
      final database = AppDatabase(_testProject, NativeDatabase.memory());
      addTearDown(database.close);

      final service = DecisionLogService(database);
      await service.record(
        ticketId: 'ticket-4',
        source: 'sddStage',
        gateResult: 'fired',
      );
      await service.record(
        ticketId: 'ticket-5',
        source: 'codingExecution',
        gateResult: 'fired',
      );

      final rows = await database.select(database.decisionLogTable).get();

      expect(rows, hasLength(2));
      expect(rows[0].id, isNotEmpty);
      expect(rows[1].id, isNotEmpty);
      expect(rows[0].id, isNot(rows[1].id));
    });
  });

  group('schema 23 — DecisionLogTable', () {
    test('a fresh onCreate install has the decision_log table, empty',
        () async {
      final database = AppDatabase(_testProject, NativeDatabase.memory());
      addTearDown(database.close);

      final rows = await database.select(database.decisionLogTable).get();

      expect(rows, isEmpty);
    });

    test(
      'an install upgraded from schema 22 has the decision_log table, empty',
      () async {
        final database = AppDatabase(
          _testProject,
          NativeDatabase.memory(
            setup: (db) => db.execute('PRAGMA user_version = 22'),
          ),
        );
        addTearDown(database.close);

        final rows = await database.select(database.decisionLogTable).get();

        expect(rows, isEmpty);
      },
    );
  });
}
