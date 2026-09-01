// presentation/cubit/workflow_config_state.dart — WorkflowConfigState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/entities/default_workflow_statuses.dart';
import 'package:aion/features/tickets/domain/entities/skill_attachment.dart';
import 'package:aion/features/tickets/domain/entities/workflow_prompt_template.dart';
import 'package:aion/features/tickets/domain/entities/workflow_status.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

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
    this.transitionPreconditionNodeCounts = const {},
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

  /// Each precondition-bearing [SddStage]'s current transition-precondition
  /// field-check count — from `TransitionPreconditionRepository
  /// .getNodeCounts`, `0`/absent when unconfigured. Powers
  /// `WorkflowStatusSettingsScreen`'s "Configure precondition" affordance
  /// count badge. Defaults to `{}` — a project built without a
  /// `TransitionPreconditionRepository` (see [WorkflowConfigCubit]'s
  /// constructor) shows every stage as unconfigured rather than failing
  /// to load. Added for
  /// `aion-arch/changes/sddstage-transition-preconditions`'s post-`/verify`
  /// follow-up.
  final Map<SddStage, int> transitionPreconditionNodeCounts;

  /// The shared-base statuses only (no per-type extensions), sorted by
  /// [WorkflowStatus.sortOrder] — the scope a cross-type surface (Board,
  /// Filters, Columns, bulk status menu) renders, since a status
  /// extension only makes sense for tickets of its own [TicketType].
  List<WorkflowStatus> get sharedBaseStatuses =>
      [for (final s in statuses.where((s) => s.ticketType == null)) s]
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// The effective status set for a single ticket of [type]: the
  /// shared-base set plus [type]'s own extensions, sorted by
  /// [WorkflowStatus.sortOrder] — the scope a single ticket's own status
  /// picker renders. Mirrors [WorkflowConfigCubit]'s own
  /// `_isNameUniqueInScope` scope definition.
  List<WorkflowStatus> effectiveStatusesForType(TicketType type) => [
    for (final s in statuses)
      if (s.ticketType == null || s.ticketType == type) s,
  ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  List<Object?> get props => [
    statuses,
    designStagesEnabled,
    stageDisplayNameOverrides,
    attachments,
    templates,
    transitionPreconditionNodeCounts,
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

/// The shared-base status names, in sortOrder — from [state] if loaded,
/// falling back to [defaultWorkflowStatuses]' own order otherwise (the
/// brief window before `WorkflowConfigCubit.load` resolves; every real
/// project seeds these exact rows, so this is never a stale value for a
/// customized project, only a momentary loading placeholder). Used by
/// every cross-type status surface — Board, Filters, Columns, the bulk
/// status menu.
List<String> resolveSharedStatusOrder(WorkflowConfigState state) =>
    switch (state) {
      WorkflowConfigLoaded(:final sharedBaseStatuses) => [
        for (final s in sharedBaseStatuses) s.name,
      ],
      _ => [for (final s in defaultWorkflowStatuses) s.name],
    };

/// The effective per-[type] status names, in sortOrder — same
/// loaded/fallback split as [resolveSharedStatusOrder]. Used by a single
/// ticket's own status picker (`ticket_metadata_section.dart`), where a
/// type-specific extension status is meaningful.
List<String> resolveStatusOrderForType(
  WorkflowConfigState state,
  TicketType type,
) => switch (state) {
  WorkflowConfigLoaded() => [
    for (final s in state.effectiveStatusesForType(type)) s.name,
  ],
  _ => [for (final s in defaultWorkflowStatuses) s.name],
};
