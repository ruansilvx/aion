// domain/entities/transition_branch.dart — TransitionBranch entity (domain layer).

import 'package:meta/meta.dart';

import 'package:aion/features/tickets/domain/enums/transition_outcome.dart';

/// One outgoing edge of a `TransitionNode` — either continues the strict
/// tree into another field check ([TransitionBranch.toNode]) or ends the
/// walk in a terminal [TransitionOutcome] ([TransitionBranch.terminal]).
/// Structurally identical in shape to `core/automation/decision_node.dart`'s
/// `DecisionBranch` but a separate type — see
/// `AIO-1936`'s "Why
/// parallel types, not shared ones." Added for
/// `AIO-1936`.
@immutable
sealed class TransitionBranch {
  const TransitionBranch();

  /// A branch that leads to another `TransitionNode`, identified by
  /// [nodeId] — the strict-tree edge. [nodeId] must never be referenced as
  /// a child from more than one branch anywhere in the same graph;
  /// enforced by `TransitionPreconditionConfigCubit`, never by this entity
  /// or by `TransitionPreconditionRepository`.
  const factory TransitionBranch.toNode(String nodeId) = ToTransitionNodeBranch;

  /// A branch that ends the walk here, resolving to [outcome].
  const factory TransitionBranch.terminal(TransitionOutcome outcome) =
      TerminalTransitionBranch;
}

/// [TransitionBranch.toNode]'s concrete implementation. Public (rather than
/// a private, factory-only-constructed class) so
/// `evaluate_transition_graph.dart`'s exhaustive `switch` can pattern-match
/// on it directly — mirrors `core/automation/decision_node.dart`'s
/// `ToNodeBranch`.
class ToTransitionNodeBranch extends TransitionBranch {
  /// Creates a [ToTransitionNodeBranch] pointing at [nodeId]. Prefer
  /// `TransitionBranch.toNode` at call sites.
  const ToTransitionNodeBranch(this.nodeId);

  /// The id of the `TransitionNode` this branch continues to.
  final String nodeId;

  @override
  bool operator ==(Object other) =>
      other is ToTransitionNodeBranch && other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(ToTransitionNodeBranch, nodeId);
}

/// [TransitionBranch.terminal]'s concrete implementation. Public for the
/// same pattern-matching reason as [ToTransitionNodeBranch].
class TerminalTransitionBranch extends TransitionBranch {
  /// Creates a [TerminalTransitionBranch] resolving to [outcome]. Prefer
  /// `TransitionBranch.terminal` at call sites.
  const TerminalTransitionBranch(this.outcome);

  /// The [TransitionOutcome] this branch resolves to.
  final TransitionOutcome outcome;

  @override
  bool operator ==(Object other) =>
      other is TerminalTransitionBranch && other.outcome == outcome;

  @override
  int get hashCode => Object.hash(TerminalTransitionBranch, outcome);
}
