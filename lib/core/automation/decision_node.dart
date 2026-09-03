// core/automation/decision_node.dart — DecisionBranch/DecisionNode entities (core layer).

import 'package:meta/meta.dart';

import 'package:aion/core/automation/decision_outcome.dart';

/// One outgoing edge of a [DecisionNode] — either continues the strict
/// tree into another condition ([DecisionBranch.toNode]) or ends the walk
/// in a terminal [DecisionOutcome] ([DecisionBranch.terminal]). Added for
/// `AIO-181`.
@immutable
sealed class DecisionBranch {
  const DecisionBranch();

  /// A branch that leads to another [DecisionNode], identified by
  /// [nodeId] — the strict-tree edge. [nodeId] must never be referenced
  /// as a child from more than one branch anywhere in the same graph;
  /// enforced by `DecisionGraphConfigCubit`, never by this entity or by
  /// `DecisionGraphRepository`.
  const factory DecisionBranch.toNode(String nodeId) = ToNodeBranch;

  /// A branch that ends the walk here, resolving to [outcome].
  const factory DecisionBranch.terminal(DecisionOutcome outcome) =
      TerminalBranch;
}

/// [DecisionBranch.toNode]'s concrete implementation. Public (rather than
/// a private, factory-only-constructed class) so
/// `decision_graph_evaluator.dart`'s exhaustive `switch` can pattern-match
/// on it directly — Dart's sealed-class rule already confines every
/// direct subtype to this library; there's no encapsulation benefit left
/// to gain by also hiding the class name itself.
class ToNodeBranch extends DecisionBranch {
  /// Creates a [ToNodeBranch] pointing at [nodeId]. Prefer
  /// `DecisionBranch.toNode` at call sites.
  const ToNodeBranch(this.nodeId);

  /// The id of the [DecisionNode] this branch continues to.
  final String nodeId;

  @override
  bool operator ==(Object other) =>
      other is ToNodeBranch && other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(ToNodeBranch, nodeId);
}

/// [DecisionBranch.terminal]'s concrete implementation. Public for the
/// same pattern-matching reason as [ToNodeBranch].
class TerminalBranch extends DecisionBranch {
  /// Creates a [TerminalBranch] resolving to [outcome]. Prefer
  /// `DecisionBranch.terminal` at call sites.
  const TerminalBranch(this.outcome);

  /// The [DecisionOutcome] this branch resolves to.
  final DecisionOutcome outcome;

  @override
  bool operator ==(Object other) =>
      other is TerminalBranch && other.outcome == outcome;

  @override
  int get hashCode => Object.hash(TerminalBranch, outcome);
}

/// One condition in a project-authored [DecisionGraph] — a strict binary
/// tree node. [conditionId] references a `DecisionConditionSpec.id` from
/// `decision_condition_catalog.dart`; [conditionParams] holds that
/// condition's parameter values (e.g. `{'maxAttempts': 3}`), validated
/// against the spec's `parameterSpecs` shape by `DecisionGraphConfigCubit`
/// at edit time — this entity itself performs no validation, per this
/// project's Cubit-vs-repository split. [matchedBranch]/[unmatchedBranch]
/// are each a [DecisionBranch] — either continues the tree or terminates
/// in a [DecisionOutcome]. Added for
/// `AIO-181`.
@immutable
class DecisionNode {
  /// Creates a [DecisionNode].
  const DecisionNode({
    required this.id,
    required this.conditionId,
    required this.conditionParams,
    required this.matchedBranch,
    required this.unmatchedBranch,
  });

  /// UUID v4 primary key.
  final String id;

  /// References a `DecisionConditionSpec.id` in
  /// `decision_condition_catalog.dart`.
  final String conditionId;

  /// This condition's parameter values, keyed by
  /// `DecisionConditionSpec.parameterSpecs` name.
  final Map<String, dynamic> conditionParams;

  /// Where the walk continues when [conditionId]'s condition evaluates
  /// `true` for the current `DecisionEvalContext`.
  final DecisionBranch matchedBranch;

  /// Where the walk continues when [conditionId]'s condition evaluates
  /// `false`.
  final DecisionBranch unmatchedBranch;

  /// Returns a copy of this node with the given fields replaced.
  DecisionNode copyWith({
    String? conditionId,
    Map<String, dynamic>? conditionParams,
    DecisionBranch? matchedBranch,
    DecisionBranch? unmatchedBranch,
  }) {
    return DecisionNode(
      id: id,
      conditionId: conditionId ?? this.conditionId,
      conditionParams: conditionParams ?? this.conditionParams,
      matchedBranch: matchedBranch ?? this.matchedBranch,
      unmatchedBranch: unmatchedBranch ?? this.unmatchedBranch,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DecisionNode &&
      other.id == id &&
      other.conditionId == conditionId &&
      _mapEquals(other.conditionParams, conditionParams) &&
      other.matchedBranch == matchedBranch &&
      other.unmatchedBranch == unmatchedBranch;

  @override
  int get hashCode =>
      Object.hash(id, conditionId, matchedBranch, unmatchedBranch);

  static bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
