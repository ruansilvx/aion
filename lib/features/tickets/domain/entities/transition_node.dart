// domain/entities/transition_node.dart — TransitionNode entity (domain layer).

import 'package:meta/meta.dart';

import 'package:aion/features/tickets/domain/entities/transition_branch.dart';

/// One field check in a project-authored `SddStage` transition-precondition
/// graph — a strict binary tree node. [fieldId] references a
/// `TransitionFieldSpec.id` from `transition_field_spec.dart`.
/// [matchedBranch]/[unmatchedBranch] are each a [TransitionBranch] — either
/// continues the tree or terminates in a `TransitionOutcome`. Simpler than
/// `core/automation/decision_node.dart`'s `DecisionNode` deliberately — there
/// is no `conditionParams`/operator/value shape here, since every field this
/// proposal ships is a plain boolean: a node is just "which field; where its
/// `true` branch goes; where its `false` branch goes." Added for `AIO-1936`.
@immutable
class TransitionNode {
  /// Creates a [TransitionNode].
  const TransitionNode({
    required this.id,
    required this.fieldId,
    required this.matchedBranch,
    required this.unmatchedBranch,
  });

  /// UUID v4 primary key.
  final String id;

  /// References a `TransitionFieldSpec.id` in `transition_field_spec.dart`.
  final String fieldId;

  /// Where the walk continues when [fieldId]'s field evaluates `true` for
  /// the current `TransitionEvalContext`.
  final TransitionBranch matchedBranch;

  /// Where the walk continues when [fieldId]'s field evaluates `false`.
  final TransitionBranch unmatchedBranch;

  /// Returns a copy of this node with the given fields replaced.
  TransitionNode copyWith({
    String? fieldId,
    TransitionBranch? matchedBranch,
    TransitionBranch? unmatchedBranch,
  }) {
    return TransitionNode(
      id: id,
      fieldId: fieldId ?? this.fieldId,
      matchedBranch: matchedBranch ?? this.matchedBranch,
      unmatchedBranch: unmatchedBranch ?? this.unmatchedBranch,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TransitionNode &&
      other.id == id &&
      other.fieldId == fieldId &&
      other.matchedBranch == matchedBranch &&
      other.unmatchedBranch == unmatchedBranch;

  @override
  int get hashCode => Object.hash(id, fieldId, matchedBranch, unmatchedBranch);
}
