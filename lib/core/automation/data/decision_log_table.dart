// core/automation/data/decision_log_table.dart — Drift table definition for decision_log (data layer).

import 'package:drift/drift.dart';

/// Drift table backing the structured decision-log audit trail for SDD cycles.
/// Row type is generated as `DecisionLogEntryData`. No FK constraints — integrity
/// is enforced at the repository layer, matching every other table in this schema.
/// Added for `AIO-2947` §1.
@DataClassName('DecisionLogEntryData')
class DecisionLogTable extends Table {
  @override
  String get tableName => 'decision_log';

  /// UUID v4 primary key.
  TextColumn get id => text()();

  /// The ticket this decision concerns — its internal UUID.
  TextColumn get ticketId => text().named('ticket_id')();

  /// [AutomationContext.name], or a literal `'skillAttachment'` / `'ideaPromotion'`
  /// for out-of-context decisions.
  TextColumn get source => text()();

  /// Nullable detail identifying the source (e.g. [WorkflowSkillAttachment.id]
  /// for `'skillAttachment'` rows, or the automation-context gate's own
  /// condition for `ideaPromotion` rows). Null when [source] is an
  /// [AutomationContext] that carries no additional context.
  TextColumn get sourceDetail => text().named('source_detail').nullable()();

  /// [AutomationConfidence.name], or null for `'ideaPromotion'` rows which
  /// have no confidence tier.
  TextColumn get confidence => text().nullable()();

  /// [DecisionOutcome.name], only populated when a decision graph was walked
  /// and produced a [DecisionOutcome]. Null when [gateResult] is `'pending'`
  /// (decision not yet reached) or `'confirmed'` / `'declined'` / `'rejected'`
  /// (user interaction overrode the graph result).
  TextColumn get outcome => text().nullable()();

  /// The terminal gate state: `'fired'` / `'pending'` / `'confirmed'` /
  /// `'rejected'` / `'declined'`.
  TextColumn get gateResult => text().named('gate_result')();

  /// Free-form context: resolved asset version, mechanical-check command +
  /// exit code, etc.
  TextColumn get detail => text().nullable()();

  /// Unix milliseconds.
  IntColumn get createdAt => integer().named('created_at')();

  @override
  Set<Column> get primaryKey => {id};
}
