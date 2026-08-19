// data/daos/workflow_skill_attachment_dao.dart — WorkflowSkillAttachmentDao Drift accessor (data layer).

import 'package:drift/drift.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/models/workflow_skill_attachment_table.dart';

part 'workflow_skill_attachment_dao.g.dart';

/// Drift accessor for [WorkflowSkillAttachmentsTable]. Plain CRUD only —
/// no seeding logic, matching [WorkflowStatusDao]'s shape minus its
/// `seedDefaultsIfEmpty` method (an empty attachment table is the correct
/// starting state — see `app_database.dart`'s version-16 dartdoc). See
/// `aion-arch/changes/workflow-skill-attachments/design.md` §2.4.
@DriftAccessor(tables: [WorkflowSkillAttachmentsTable])
class WorkflowSkillAttachmentDao extends DatabaseAccessor<AppDatabase>
    with _$WorkflowSkillAttachmentDaoMixin {
  /// Creates a [WorkflowSkillAttachmentDao] bound to [db].
  WorkflowSkillAttachmentDao(super.db);

  /// Returns every persisted row, unfiltered.
  Future<List<WorkflowSkillAttachmentData>> getAll() {
    return select(workflowSkillAttachmentsTable).get();
  }

  /// Inserts a single new row.
  Future<void> insertOne(WorkflowSkillAttachmentsTableCompanion companion) {
    return into(workflowSkillAttachmentsTable).insert(companion);
  }

  /// Updates a single existing row (matched by its primary key).
  Future<void> updateOne(WorkflowSkillAttachmentsTableCompanion companion) {
    return update(workflowSkillAttachmentsTable).replace(companion);
  }

  /// Deletes the row with id [id].
  Future<void> deleteOne(String id) {
    return (delete(
      workflowSkillAttachmentsTable,
    )..where((t) => t.id.equals(id))).go();
  }
}
