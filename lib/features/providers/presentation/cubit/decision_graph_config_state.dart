// presentation/cubit/decision_graph_config_state.dart — DecisionGraphConfigState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/decision_graph.dart';
import 'package:aion/core/automation/decision_node.dart';

/// The state emitted by
/// [DecisionGraphConfigCubit](decision_graph_config_cubit.dart).
sealed class DecisionGraphConfigState extends Equatable {
  const DecisionGraphConfigState();

  @override
  List<Object?> get props => [];
}

/// Initial state, before [DecisionGraphConfigCubit.load] resolves.
class DecisionGraphConfigInitial extends DecisionGraphConfigState {
  /// Creates a [DecisionGraphConfigInitial] state.
  const DecisionGraphConfigInitial();
}

/// Loaded — carries the [AutomationContext] currently being edited, its
/// [DecisionGraph], and every [DecisionNode] reachable from that graph's
/// root, keyed by id. `DecisionGraphEditorScreen`'s canvas and outline
/// panes both render from this one state and call the same
/// [DecisionGraphConfigCubit] methods, so the two panes can never
/// diverge.
class DecisionGraphConfigLoaded extends DecisionGraphConfigState {
  /// Creates a [DecisionGraphConfigLoaded] state.
  const DecisionGraphConfigLoaded({
    required this.context,
    required this.graph,
    required this.nodesById,
  });

  /// Which [AutomationContext] this state is editing.
  final AutomationContext context;

  /// The currently-configured [DecisionGraph] for [context].
  final DecisionGraph graph;

  /// Every [DecisionNode] reachable from [graph]'s root, keyed by
  /// [DecisionNode.id].
  final Map<String, DecisionNode> nodesById;

  @override
  List<Object?> get props => [context, graph, nodesById];
}

/// Why an attempted [DecisionGraphConfigCubit] write was rejected —
/// classified rather than a pre-built message string, since a `Cubit` has
/// no `BuildContext` to localize through (see
/// `aion-arch/flutter-conventions.md`'s Localization section). Resolved
/// to display text by a co-located
/// `decisionGraphConfigErrorMessage(BuildContext, ...)` function in the
/// widgets layer — mirrors `TicketsErrorReason`/`ticketsErrorMessage`'s
/// exact shape.
enum DecisionGraphConfigErrorReason {
  /// The node being updated/rooted-to/branched-to no longer exists in
  /// the loaded tree.
  nodeNotFound,

  /// A branch points at a node id absent from the resulting node set.
  danglingBranchTarget,

  /// A node id would be referenced as a child from more than one branch.
  duplicateChildReference,

  /// Walking from the graph's root would revisit a node.
  cycleDetected,
}

/// An attempted write was rejected — a strict-tree-invariant violation
/// (see [DecisionGraphConfigCubit]'s dartdoc). Carries [previous] (the
/// last known-good [DecisionGraphConfigLoaded] state) so the editor never
/// loses its tree while showing the rejection [reason] — mirrors
/// `WorkflowConfigError`'s exact shape, classified per this project's
/// Cubit-localization convention.
class DecisionGraphConfigError extends DecisionGraphConfigState {
  /// Creates a [DecisionGraphConfigError] state.
  const DecisionGraphConfigError({
    required this.reason,
    required this.previous,
  });

  /// Why the attempted write was rejected.
  final DecisionGraphConfigErrorReason reason;

  /// The last successfully loaded state, preserved so the editor keeps
  /// rendering the tree unchanged alongside the error.
  final DecisionGraphConfigLoaded previous;

  @override
  List<Object?> get props => [reason, previous];
}
