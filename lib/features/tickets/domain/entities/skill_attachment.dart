// domain/entities/skill_attachment.dart — SkillAttachment entity (domain layer).

import 'package:equatable/equatable.dart';

import 'package:aion/core/automation/automation_confidence.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/skill_attachment_kind.dart';

/// A project-configured automation attached to either a
/// `WorkflowStatus`(../entities/workflow_status.dart) or an [SddStage] —
/// the Phase 2 mechanism that makes entering that status/stage run an AI
/// action, rather than nothing (Phase 1's baseline). See
/// `AIO-2650` §1.2.
///
/// Exactly one of [workflowStatusId]/[sddStage] is non-`null` (what this
/// attachment is *for*); exactly one of [templateId]/[skillName] is
/// non-`null`, matching [kind] (what it *runs*). Neither invariant is
/// enforced here — this entity performs no validation, mirroring
/// `WorkflowStatus`'s own precedent; both are enforced by
/// `WorkflowConfigCubit`.
class SkillAttachment extends Equatable {
  /// Internal UUID v4 primary key.
  final String id;

  /// The `WorkflowStatus.id` this attachment fires on entry to, or `null`
  /// when this attachment is for an [sddStage] instead.
  final String? workflowStatusId;

  /// The [SddStage] this attachment fires on entry to, or `null` when
  /// this attachment is for a [workflowStatusId] instead.
  final SddStage? sddStage;

  /// Which mechanism this attachment runs.
  final SkillAttachmentKind kind;

  /// The `WorkflowPromptTemplate.id` to render, non-`null` only when
  /// [kind] is [SkillAttachmentKind.aionNativeTemplate].
  final String? templateId;

  /// The literal skill name (no leading `/`) to delegate to, non-`null`
  /// only when [kind] is [SkillAttachmentKind.delegatedSkill].
  final String? skillName;

  /// How aggressively this attachment fires when its target is entered.
  final AutomationConfidence confidence;

  /// Creates a [SkillAttachment].
  const SkillAttachment({
    required this.id,
    this.workflowStatusId,
    this.sddStage,
    required this.kind,
    this.templateId,
    this.skillName,
    required this.confidence,
  });

  @override
  List<Object?> get props => [
    id,
    workflowStatusId,
    sddStage,
    kind,
    templateId,
    skillName,
    confidence,
  ];

  /// Returns a copy of this attachment with the given fields replaced.
  /// [workflowStatusId]/[sddStage]/[templateId]/[skillName] are nullable
  /// and therefore take a zero-arg setter — pass `() => null` to
  /// explicitly clear one of them, or omit the parameter entirely to
  /// leave it unchanged, mirroring `WorkflowStatus.copyWith`'s own
  /// convention.
  SkillAttachment copyWith({
    String? Function()? workflowStatusId,
    SddStage? Function()? sddStage,
    SkillAttachmentKind? kind,
    String? Function()? templateId,
    String? Function()? skillName,
    AutomationConfidence? confidence,
  }) {
    return SkillAttachment(
      id: id,
      workflowStatusId: workflowStatusId != null
          ? workflowStatusId()
          : this.workflowStatusId,
      sddStage: sddStage != null ? sddStage() : this.sddStage,
      kind: kind ?? this.kind,
      templateId: templateId != null ? templateId() : this.templateId,
      skillName: skillName != null ? skillName() : this.skillName,
      confidence: confidence ?? this.confidence,
    );
  }
}
