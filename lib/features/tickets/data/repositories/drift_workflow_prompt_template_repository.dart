// data/repositories/drift_workflow_prompt_template_repository.dart — Drift implementation of WorkflowPromptTemplateRepository (data layer).

import 'package:drift/drift.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/domain/entities/workflow_prompt_template.dart';
import 'package:aion/features/tickets/domain/repositories/workflow_prompt_template_repository.dart';

/// Drift-backed implementation of [WorkflowPromptTemplateRepository]. No
/// business logic here — maps [WorkflowPromptTemplateData] rows to
/// [WorkflowPromptTemplate] entities and delegates every method straight
/// to [WorkflowPromptTemplateDao], matching
/// [DriftWorkflowStatusRepository]'s exact shape. No `onChanged` stream —
/// [WorkflowPromptTemplateRepository] doesn't declare one, since only
/// `WorkflowConfigCubit` reads templates today (via its own `load()`
/// re-fetch after each mutating call), unlike `SkillAttachment`s which
/// `TicketsCubit` also caches independently.
class DriftWorkflowPromptTemplateRepository
    implements WorkflowPromptTemplateRepository {
  /// Creates a [DriftWorkflowPromptTemplateRepository] backed by [_db].
  DriftWorkflowPromptTemplateRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<WorkflowPromptTemplate>> getAll() async {
    final rows = await _db.workflowPromptTemplateDao.getAll();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> create(WorkflowPromptTemplate template) {
    return _db.workflowPromptTemplateDao.insertOne(_toCompanion(template));
  }

  @override
  Future<void> update(WorkflowPromptTemplate template) {
    return _db.workflowPromptTemplateDao.updateOne(_toCompanion(template));
  }

  @override
  Future<void> delete(String id) {
    return _db.workflowPromptTemplateDao.deleteOne(id);
  }

  /// Maps a domain [WorkflowPromptTemplate] to its persisted-row
  /// companion.
  WorkflowPromptTemplatesTableCompanion _toCompanion(
    WorkflowPromptTemplate template,
  ) {
    return WorkflowPromptTemplatesTableCompanion(
      id: Value(template.id),
      name: Value(template.name),
      body: Value(template.body),
    );
  }

  /// Maps a generated [WorkflowPromptTemplateData] row to the
  /// [WorkflowPromptTemplate] domain entity.
  WorkflowPromptTemplate _toEntity(WorkflowPromptTemplateData row) {
    return WorkflowPromptTemplate(id: row.id, name: row.name, body: row.body);
  }
}
