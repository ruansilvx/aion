// data/repositories/drift_workflow_skill_attachment_repository.dart — Drift implementation of WorkflowSkillAttachmentRepository (data layer).

import 'dart:async';

import 'package:drift/drift.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/domain/entities/skill_attachment.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/skill_attachment_kind.dart';
import 'package:aion/features/tickets/domain/repositories/workflow_skill_attachment_repository.dart';

/// Drift-backed implementation of [WorkflowSkillAttachmentRepository]. No
/// business logic here — maps [WorkflowSkillAttachmentData] rows to
/// [SkillAttachment] entities and delegates every method straight to
/// [WorkflowSkillAttachmentDao], matching
/// [DriftWorkflowStatusRepository]'s exact shape.
class DriftWorkflowSkillAttachmentRepository
    implements WorkflowSkillAttachmentRepository {
  /// Creates a [DriftWorkflowSkillAttachmentRepository] backed by [_db].
  DriftWorkflowSkillAttachmentRepository(this._db);

  final AppDatabase _db;

  /// Broadcast controller backing [onChanged] — fired after every
  /// successful write below. `sync: true` since listeners (`TicketsCubit`/
  /// `WorkflowConfigCubit`) only ever re-read state asynchronously in
  /// response, never re-enter this repository synchronously.
  final _changeController = StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get onChanged => _changeController.stream;

  @override
  Future<List<SkillAttachment>> getAll() async {
    final rows = await _db.workflowSkillAttachmentDao.getAll();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> create(SkillAttachment attachment) async {
    await _db.workflowSkillAttachmentDao.insertOne(_toCompanion(attachment));
    _changeController.add(null);
  }

  @override
  Future<void> update(SkillAttachment attachment) async {
    await _db.workflowSkillAttachmentDao.updateOne(_toCompanion(attachment));
    _changeController.add(null);
  }

  @override
  Future<void> delete(String id) async {
    await _db.workflowSkillAttachmentDao.deleteOne(id);
    _changeController.add(null);
  }

  /// Maps a domain [SkillAttachment] to its persisted-row companion.
  WorkflowSkillAttachmentsTableCompanion _toCompanion(
    SkillAttachment attachment,
  ) {
    return WorkflowSkillAttachmentsTableCompanion(
      id: Value(attachment.id),
      workflowStatusId: Value(attachment.workflowStatusId),
      sddStage: Value(attachment.sddStage?.name),
      kind: Value(attachment.kind.name),
      templateId: Value(attachment.templateId),
      skillName: Value(attachment.skillName),
      confidence: Value(attachment.confidence.name),
    );
  }

  /// Maps a generated [WorkflowSkillAttachmentData] row to the
  /// [SkillAttachment] domain entity.
  SkillAttachment _toEntity(WorkflowSkillAttachmentData row) {
    return SkillAttachment(
      id: row.id,
      workflowStatusId: row.workflowStatusId,
      sddStage: _parseNullableEnum(SddStage.values, row.sddStage),
      kind:
          _parseNullableEnum(SkillAttachmentKind.values, row.kind) ??
          SkillAttachmentKind.aionNativeTemplate,
      templateId: row.templateId,
      skillName: row.skillName,
      confidence:
          _parseNullableEnum(AutomationConfidence.values, row.confidence) ??
          AutomationConfidence.gated,
    );
  }

  /// Parses [name] against [values] by `.name`, returning `null` if [name]
  /// is `null` or doesn't match any value.
  T? _parseNullableEnum<T extends Enum>(List<T> values, String? name) {
    if (name == null) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
