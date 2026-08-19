// data/models/workflow_skill_attachment_table.dart — Drift table definition for workflow_skill_attachments (data layer).

import 'package:drift/drift.dart';

/// Drift table persisting a project's configured
/// `SkillAttachment`(../../domain/entities/skill_attachment.dart) set —
/// the automation attached to a `WorkflowStatus` or `SddStage` entry. Row
/// type is generated as `WorkflowSkillAttachmentData`. No FK constraints
/// — integrity is enforced at the `WorkflowConfigCubit` layer, matching
/// `WorkflowStatusesTable`'s own precedent. See
/// `aion-arch/changes/workflow-skill-attachments/design.md` §2.1.
@DataClassName('WorkflowSkillAttachmentData')
class WorkflowSkillAttachmentsTable extends Table {
  @override
  String get tableName => 'workflow_skill_attachments';

  /// Internal UUID v4 primary key.
  TextColumn get id => text()();

  /// The `WorkflowStatus.id` this attachment fires on entry to, nullable
  /// — exactly one of this and [sddStage] is non-`null`.
  TextColumn get workflowStatusId =>
      text().named('workflow_status_id').nullable()();

  /// `SddStage.name` this attachment fires on entry to, nullable — exactly
  /// one of this and [workflowStatusId] is non-`null`.
  TextColumn get sddStage => text().named('sdd_stage').nullable()();

  /// `SkillAttachmentKind.name`.
  TextColumn get kind => text()();

  /// The `WorkflowPromptTemplate.id` to render, nullable — set only when
  /// [kind] is `aionNativeTemplate`.
  TextColumn get templateId => text().named('template_id').nullable()();

  /// The literal skill name to delegate to, nullable — set only when
  /// [kind] is `delegatedSkill`.
  TextColumn get skillName => text().named('skill_name').nullable()();

  /// `AutomationConfidence.name`.
  TextColumn get confidence => text()();

  @override
  Set<Column> get primaryKey => {id};
}
