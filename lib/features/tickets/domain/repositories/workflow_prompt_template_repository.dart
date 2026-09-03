// domain/repositories/workflow_prompt_template_repository.dart — WorkflowPromptTemplateRepository interface (domain layer).

import 'package:aion/features/tickets/domain/entities/workflow_prompt_template.dart';

/// Read/write access to [WorkflowPromptTemplate] persistence. A dumb
/// persistence layer only — no validation, no invariant enforcement (e.g.
/// project-wide name uniqueness, or rejecting a delete while a live
/// `SkillAttachment` still references the template). Every domain
/// invariant lives in `WorkflowConfigCubit`, per this project's
/// Cubit-vs-repository split. Implemented by the data layer
/// ([DriftWorkflowPromptTemplateRepository]); UI and domain code depend
/// only on this interface, never on a concrete data source. See
/// `AIO-2650` §1.6.
abstract interface class WorkflowPromptTemplateRepository {
  /// Returns every persisted [WorkflowPromptTemplate], unfiltered.
  Future<List<WorkflowPromptTemplate>> getAll();

  /// Persists a new [template] row.
  Future<void> create(WorkflowPromptTemplate template);

  /// Persists [template]'s current field values over its existing row
  /// (matched by [WorkflowPromptTemplate.id]).
  Future<void> update(WorkflowPromptTemplate template);

  /// Deletes the template with id [id].
  Future<void> delete(String id);
}
