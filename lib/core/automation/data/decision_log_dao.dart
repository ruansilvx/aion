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

  /// Records a single decision-log entry. Must never throw into its caller —
  /// a logging bug must never block or corrupt a real gate. Wraps the actual
  /// DB write in try/catch, matching [MechanicalVerificationRunner]'s
  /// "must not break a real decision" bar.
  Future<void> record({
    required String ticketId,
    required String source,
    String? sourceDetail,
    String? confidence,
    String? outcome,
    required String gateResult,
    String? detail,
  }) async {
    try {
      await into(decisionLogTable).insert(
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
    } catch (e) {
      // Swallow the exception to prevent logging bugs from breaking real
      // decision gates. In production, this would be logged to a diagnostics
      // service; for now, a silent failure is acceptable given this table's
      // audit-trail-only purpose (it does not drive any business logic).
    }
  }
}
