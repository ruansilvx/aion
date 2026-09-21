// data/models/decision_log_table.dart — Drift table definition for decision_log (data layer).

import 'package:drift/drift.dart';

/// Drift table persisting an audit trail of decisions made during the SDD
/// cycle — when a transition graph or automation decision was evaluated,
/// which fields were checked, and what the outcome was. Row type is generated
/// as `DecisionLogEntryData`. No FK constraints — integrity is enforced at
/// the repository layer, matching every other table in this schema. Added for
/// `AIO-2947`.
@DataClassName('DecisionLogEntryData')
class DecisionLogsTable extends Table {
  @override
  String get tableName => 'decision_logs';

  /// UUID v4 primary key.
  TextColumn get id => text()();

  /// The ticket id this decision concerns.
  TextColumn get ticketId => text().named('ticket_id')();

  /// The field id that was evaluated (e.g., `"designSyncApproved"`,
  /// `"verifyGateApproved"`), matching a [TransitionFieldSpec.id] or
  /// [DecisionFieldSpec.id].
  TextColumn get fieldId => text().named('field_id')();

  /// The evaluated value of the field — typically `'true'`/`'false'` for
  /// boolean fields, but represented as text to accommodate future field types.
  TextColumn get fieldValue => text().named('field_value')();

  /// The outcome of the decision: `'allowed'`/`'blocked'` matching
  /// [TransitionOutcome], or `'proceed'`/`'gated'`/`'decline'`/`'modelJudgment'`
  /// matching [DecisionOutcome].
  TextColumn get outcome => text()();

  /// Unix milliseconds timestamp when this decision was recorded.
  IntColumn get recordedAt => integer().named('recorded_at')();

  @override
  Set<Column> get primaryKey => {id};
}
