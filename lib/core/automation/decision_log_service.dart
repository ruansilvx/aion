// core/automation/decision_log_service.dart — Non-throwing decision-log writer (core layer).

import 'package:aion/core/core.dart';

/// Writes decision-log entries without throwing, preventing logging bugs from
/// breaking real decision gates. All exceptions are silently swallowed —
/// the audit trail is a best-effort observability tool, never part of the
/// critical path. See `AIO-2947` §1.
class DecisionLogService {
  /// Creates a [DecisionLogService] backed by [_db].
  DecisionLogService(this._db);

  final AppDatabase _db;

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
      await _db.decisionLogDao.insert(
        ticketId: ticketId,
        source: source,
        sourceDetail: sourceDetail,
        confidence: confidence,
        outcome: outcome,
        gateResult: gateResult,
        detail: detail,
      );
    } catch (e) {
      // Swallow the exception to prevent logging bugs from breaking real
      // decision gates. In production, this would be logged to a diagnostics
      // service; for now, a silent failure is acceptable given this table's
      // audit-trail-only purpose (it does not drive any business logic).
    }
  }
}
