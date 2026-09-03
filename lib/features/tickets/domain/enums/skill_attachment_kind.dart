// domain/enums/skill_attachment_kind.dart — SkillAttachmentKind enum (domain layer).

/// Which of the two Phase 2 attachment mechanisms a
/// [SkillAttachment](../entities/skill_attachment.dart) uses. See
/// `AIO-2650` §1.1.
enum SkillAttachmentKind {
  /// Renders a project-authored
  /// [WorkflowPromptTemplate](../entities/workflow_prompt_template.dart)
  /// against the triggering ticket (via
  /// `renderWorkflowPromptTemplate`) and runs it text-only
  /// (`AgentRequest.toolsEnabled: false`) — exactly like today's
  /// hardcoded `TicketsCubit._assembleStageContext` prompts.
  aionNativeTemplate,

  /// Sends `/<skillName>` as the run's prompt, tool-enabled
  /// (`AgentRequest.toolsEnabled: true`), so the underlying coding
  /// agent's own discovered `.claude/skills/<skillName>` skill executes.
  /// Confirmed viable by the 2026-08-19 CLI-delegation spike documented
  /// in `AIO-18`'s
  /// "Explore findings" section.
  delegatedSkill,
}
