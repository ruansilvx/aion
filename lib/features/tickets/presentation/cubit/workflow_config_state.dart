// presentation/cubit/workflow_config_state.dart — WorkflowConfigState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/entities/skill_attachment.dart';
import 'package:aion/features/tickets/domain/entities/workflow_prompt_template.dart';
import 'package:aion/features/tickets/domain/entities/workflow_status.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';

/// The state emitted by
/// [WorkflowConfigCubit](workflow_config_cubit.dart).
sealed class WorkflowConfigState extends Equatable {
  const WorkflowConfigState();

  @override
  List<Object?> get props => [];
}

/// Initial state, before [WorkflowConfigCubit.load] resolves.
class WorkflowConfigInitial extends WorkflowConfigState {
  /// Creates a [WorkflowConfigInitial] state.
  const WorkflowConfigInitial();
}

/// Loaded — carries the project's full configured [WorkflowStatus] set
/// (every scope: shared base plus every per-type extension) and its
/// `SddStage` configuration.
class WorkflowConfigLoaded extends WorkflowConfigState {
  /// Creates a [WorkflowConfigLoaded] state.
  const WorkflowConfigLoaded({
    required this.statuses,
    required this.designStagesEnabled,
    required this.stageDisplayNameOverrides,
    required this.attachments,
    required this.templates,
  });

  /// Every configured [WorkflowStatus] — base and every per-type
  /// extension together, unfiltered. A scope-specific view (base ∪ one
  /// [TicketType](../../domain/enums/ticket_type.dart)'s extensions,
  /// sorted by [WorkflowStatus.sortOrder]) is derived by the UI from this
  /// list, not stored separately.
  final List<WorkflowStatus> statuses;

  /// Whether Epics/Stories must clear the `designBrief`/`designSync`
  /// stage cycle before execution.
  final bool designStagesEnabled;

  /// The persisted display-name override for each [SddStage] that has
  /// one. A stage absent from this map uses its own hardcoded default
  /// name.
  final Map<SddStage, String> stageDisplayNameOverrides;

  /// Every configured [SkillAttachment], unfiltered — at most one per
  /// `WorkflowStatus.id`/[SddStage], enforced by
  /// [WorkflowConfigCubit.createAttachment]/[WorkflowConfigCubit.updateAttachment].
  /// Added for `aion-arch/changes/workflow-skill-attachments`.
  final List<SkillAttachment> attachments;

  /// Every configured [WorkflowPromptTemplate], unfiltered — a flat,
  /// project-wide namespace by [WorkflowPromptTemplate.name]. Added for
  /// `aion-arch/changes/workflow-skill-attachments`.
  final List<WorkflowPromptTemplate> templates;

  @override
  List<Object?> get props => [
    statuses,
    designStagesEnabled,
    stageDisplayNameOverrides,
    attachments,
    templates,
  ];
}

/// An attempted write was rejected — a name-uniqueness or role-invariant
/// violation (see [WorkflowConfigCubit]'s per-method dartdoc). Carries
/// [previous] (the last known-good [WorkflowConfigLoaded] state) so the
/// settings screen never loses its list while showing the rejection
/// reason in [message].
class WorkflowConfigError extends WorkflowConfigState {
  /// Creates a [WorkflowConfigError] state.
  const WorkflowConfigError({required this.message, required this.previous});

  /// Human-readable explanation of why the attempted write was rejected.
  final String message;

  /// The last successfully loaded state, preserved so the UI keeps
  /// rendering the status list/SDD settings unchanged alongside the error.
  final WorkflowConfigLoaded previous;

  @override
  List<Object?> get props => [message, previous];
}
