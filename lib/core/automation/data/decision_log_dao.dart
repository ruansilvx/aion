// core/automation/data/decision_log_dao.dart — DecisionLogDao Drift accessor (data layer).

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/core.dart';
import 'package:aion/core/automation/data/decision_log_table.dart';

part 'decision_log_dao.g.dart';

/// Drift accessor for [DecisionLogTable]. See `AIO-2947` §1.
@DriftAccessor(tables: [DecisionLogTable])
class DecisionLogDao extends DatabaseAccessor<AppDatabase>
    with _$DecisionLogDaoMixin {
  /// Creates a [DecisionLogDao] bound to [db].
  DecisionLogDao(super.db);

  static const _uuid = Uuid();

  /// Inserts a single decision-log entry into the database without exception
  /// handling. Callers should wrap this in try/catch if they need
  /// non-throwing semantics.
  Future<void> insert({
    required String ticketId,
    required String source,
    String? sourceDetail,
    String? confidence,
    String? outcome,
    required String gateResult,
    String? detail,
  }) {
    return into(decisionLogTable).insert(
      DecisionLogTableCompanion.insert(
        id: _uuid.v4(),
        ticketId: ticketId,
        source: source,
        sourceDetail: Value(sourceDetail),
        confidence: Value(confidence),
        outcome: Value(outcome),
        gateResult: gateResult,
        detail: Value(detail),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
