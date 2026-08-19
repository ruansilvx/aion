// domain/entities/workflow_prompt_template.dart — WorkflowPromptTemplate entity (domain layer).

import 'package:equatable/equatable.dart';

/// A project-authored, reusable prompt a
/// [SkillAttachment](skill_attachment.dart) of kind
/// [SkillAttachmentKind.aionNativeTemplate](../enums/skill_attachment_kind.dart)
/// renders and runs. See
/// `aion-arch/changes/workflow-skill-attachments/design.md` §1.3.
///
/// [name] is unique project-wide — a flat namespace, unlike
/// `WorkflowStatus.name`'s per-scope uniqueness, since one template may be
/// reused by more than one attachment across different statuses/stages.
class WorkflowPromptTemplate extends Equatable {
  /// Internal UUID v4 primary key.
  final String id;

  /// The human-readable label shown in the template picker/management
  /// screen, e.g. `"Repro Steps Request"`. Unique project-wide.
  final String name;

  /// The plain-text prompt body, optionally containing
  /// `{{ticket.title}}`-style placeholders — see
  /// `renderWorkflowPromptTemplate` (../utils/render_workflow_prompt_template.dart)
  /// for the supported variable set.
  final String body;

  /// Creates a [WorkflowPromptTemplate].
  const WorkflowPromptTemplate({
    required this.id,
    required this.name,
    required this.body,
  });

  @override
  List<Object?> get props => [id, name, body];

  /// Returns a copy of this template with the given fields replaced.
  WorkflowPromptTemplate copyWith({String? name, String? body}) {
    return WorkflowPromptTemplate(
      id: id,
      name: name ?? this.name,
      body: body ?? this.body,
    );
  }
}
