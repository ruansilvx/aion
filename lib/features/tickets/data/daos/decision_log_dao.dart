// data/daos/decision_log_dao.dart — DecisionLogDao with insert method (data layer).

import 'package:drift/drift.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/models/decision_log_table.dart';

part 'decision_log_dao.g.dart';

/// Drift accessor for [DecisionLogsTable]. Persists an audit trail of
/// decisions made during the SDD cycle. Added for `AIO-2947`.
@DriftAccessor(tables: [DecisionLogsTable])
class DecisionLogDao extends DatabaseAccessor<AppDatabase>
    with _$DecisionLogDaoMixin {
  /// Creates a [DecisionLogDao] bound to [db].
  DecisionLogDao(super.db);

  /// Inserts one row into [DecisionLogsTable]. Throws if the insert fails
  /// (e.g., on a constraint violation).
  Future<void> insert(DecisionLogsTableCompanion companion) {
    return into(decisionLogsTable).insert(companion);
  }
}
