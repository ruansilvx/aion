// data/models/workflow_prompt_template_table.dart — Drift table definition for workflow_prompt_templates (data layer).

import 'package:drift/drift.dart';

/// Drift table persisting a project's
/// `WorkflowPromptTemplate`(../../domain/entities/workflow_prompt_template.dart)
/// set — reusable, named prompt bodies a `SkillAttachment` of kind
/// `aionNativeTemplate` renders. Row type is generated as
/// `WorkflowPromptTemplateData`. No FK constraints, matching
/// `WorkflowStatusesTable`'s own precedent. See `AIO-2650` §2.2.
@DataClassName('WorkflowPromptTemplateData')
class WorkflowPromptTemplatesTable extends Table {
  @override
  String get tableName => 'workflow_prompt_templates';

  /// Internal UUID v4 primary key.
  TextColumn get id => text()();

  /// The human-readable label. Unique project-wide — enforced by
  /// `WorkflowConfigCubit`, not this table.
  TextColumn get name => text()();

  /// The plain-text prompt body, optionally containing `{{variable}}`
  /// placeholders.
  TextColumn get body => text()();

  @override
  Set<Column> get primaryKey => {id};
}
