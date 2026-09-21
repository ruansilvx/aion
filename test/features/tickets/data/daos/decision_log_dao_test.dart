// test/features/tickets/data/daos/decision_log_dao_test.dart — DecisionLogDao persistence-behavior tests.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/tickets/data/daos/decision_log_dao.dart';

/// Dummy project — [AppDatabase] requires per-project addressing, unused
/// here since every test passes an explicit in-memory executor.
final _testProject = Project(
  id: 'test-project',
  name: 'Test Project',
  storageKey: 'test-project',
  baselineVersion: '0.1.0',
  createdAt: DateTime(2024, 1, 1),
  lastOpenedAt: DateTime(2024, 1, 1),
);

/// Direct [DecisionLogDao] tests against a real in-memory drift instance.
/// Added for `AIO-2947`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late DecisionLogDao dao;
  const uuid = Uuid();

  setUp(() {
    database = AppDatabase(_testProject, NativeDatabase.memory());
    dao = database.decisionLogDao;
  });

  tearDown(() async {
    await database.close();
  });

  group('insert', () {
    test('persists a decision log entry', () async {
      final entryId = uuid.v4();
      final ticketId = uuid.v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      await dao.insert(
        DecisionLogsTableCompanion(
          id: Value(entryId),
          ticketId: Value(ticketId),
          fieldId: Value('designSyncApproved'),
          fieldValue: Value('true'),
          outcome: Value('allowed'),
          recordedAt: Value(now),
        ),
      );

      // Verify the row was inserted by selecting it back.
      final rows = await (database.select(database.decisionLogsTable)
            ..where((t) => t.id.equals(entryId)))
          .get();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.id, entryId);
      expect(row.ticketId, ticketId);
      expect(row.fieldId, 'designSyncApproved');
      expect(row.fieldValue, 'true');
      expect(row.outcome, 'allowed');
      expect(row.recordedAt, now);
    });

    test('persists entries with different field types', () async {
      final ticket1 = uuid.v4();
      final ticket2 = uuid.v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      await dao.insert(
        DecisionLogsTableCompanion(
          id: Value(uuid.v4()),
          ticketId: Value(ticket1),
          fieldId: Value('verifyGateApproved'),
          fieldValue: Value('false'),
          outcome: Value('blocked'),
          recordedAt: Value(now),
        ),
      );

      await dao.insert(
        DecisionLogsTableCompanion(
          id: Value(uuid.v4()),
          ticketId: Value(ticket2),
          fieldId: Value('proposeGateApproved'),
          fieldValue: Value('true'),
          outcome: Value('proceed'),
          recordedAt: Value(now + 1),
        ),
      );

      final rows = await database.select(database.decisionLogsTable).get();
      expect(rows, hasLength(2));
      expect(rows[0].fieldId, 'verifyGateApproved');
      expect(rows[0].outcome, 'blocked');
      expect(rows[1].fieldId, 'proposeGateApproved');
      expect(rows[1].outcome, 'proceed');
    });

    test('persists entries for the same ticket with different decisions', () async {
      final ticketId = uuid.v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      await dao.insert(
        DecisionLogsTableCompanion(
          id: Value(uuid.v4()),
          ticketId: Value(ticketId),
          fieldId: Value('hasChildren'),
          fieldValue: Value('true'),
          outcome: Value('allowed'),
          recordedAt: Value(now),
        ),
      );

      await dao.insert(
        DecisionLogsTableCompanion(
          id: Value(uuid.v4()),
          ticketId: Value(ticketId),
          fieldId: Value('allChildrenComplete'),
          fieldValue: Value('false'),
          outcome: Value('blocked'),
          recordedAt: Value(now + 1000),
        ),
      );

      final rows = await database.select(database.decisionLogsTable).get();
      expect(rows, hasLength(2));
      expect(rows[0].ticketId, ticketId);
      expect(rows[1].ticketId, ticketId);
      expect(rows[0].fieldId, 'hasChildren');
      expect(rows[1].fieldId, 'allChildrenComplete');
    });
  });
}
