// data/daos/workflow_prompt_template_dao.dart — WorkflowPromptTemplateDao Drift accessor (data layer).

import 'package:drift/drift.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/models/workflow_prompt_template_table.dart';

part 'workflow_prompt_template_dao.g.dart';

/// Drift accessor for [WorkflowPromptTemplatesTable]. Plain CRUD only —
/// no seeding logic, matching [WorkflowSkillAttachmentDao]'s shape. See
/// `aion-arch/changes/workflow-skill-attachments/design.md` §2.4.
@DriftAccessor(tables: [WorkflowPromptTemplatesTable])
class WorkflowPromptTemplateDao extends DatabaseAccessor<AppDatabase>
    with _$WorkflowPromptTemplateDaoMixin {
  /// Creates a [WorkflowPromptTemplateDao] bound to [db].
  WorkflowPromptTemplateDao(super.db);

  /// Returns every persisted row, unfiltered.
  Future<List<WorkflowPromptTemplateData>> getAll() {
    return select(workflowPromptTemplatesTable).get();
  }

  /// Inserts a single new row.
  Future<void> insertOne(WorkflowPromptTemplatesTableCompanion companion) {
    return into(workflowPromptTemplatesTable).insert(companion);
  }

  /// Updates a single existing row (matched by its primary key).
  Future<void> updateOne(WorkflowPromptTemplatesTableCompanion companion) {
    return update(workflowPromptTemplatesTable).replace(companion);
  }

  /// Deletes the row with id [id].
  Future<void> deleteOne(String id) {
    return (delete(
      workflowPromptTemplatesTable,
    )..where((t) => t.id.equals(id))).go();
  }
}
