// domain/repositories/workflow_skill_attachment_repository.dart — WorkflowSkillAttachmentRepository interface (domain layer).

import 'package:aion/features/tickets/domain/entities/skill_attachment.dart';

/// Read/write access to [SkillAttachment] persistence. A dumb persistence
/// layer only — no validation, no invariant enforcement (e.g. the
/// at-most-one-per-target rule). Every domain invariant lives in
/// `WorkflowConfigCubit`, per this project's Cubit-vs-repository split
/// (validation/invariant logic lives in Cubits, not repositories).
/// Implemented by the data layer
/// ([DriftWorkflowSkillAttachmentRepository]); UI and domain code depend
/// only on this interface, never on a concrete data source. See
/// `AIO-2650` §1.5.
abstract interface class WorkflowSkillAttachmentRepository {
  /// Returns every persisted [SkillAttachment], unfiltered.
  Future<List<SkillAttachment>> getAll();

  /// Persists a new [attachment] row.
  Future<void> create(SkillAttachment attachment);

  /// Persists [attachment]'s current field values over its existing row
  /// (matched by [SkillAttachment.id]).
  Future<void> update(SkillAttachment attachment);

  /// Deletes the attachment with id [id].
  Future<void> delete(String id);

  /// Fires (with no payload) after every successful [create]/[update]/
  /// [delete] write. This is the "config changed" signal `TicketsCubit`'s
  /// cached `_skillAttachments` copy and `WorkflowConfigCubit`'s own
  /// state subscribe to, so the two Cubits stay consistent through the
  /// repository layer rather than holding a direct reference to each
  /// other — mirrors `WorkflowStatusRepository.onChanged`'s exact
  /// precedent.
  Stream<void> get onChanged;
}
