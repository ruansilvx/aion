// presentation/cubit/transition_precondition_config_state.dart — TransitionPreconditionConfigState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/entities/transition_node.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/repositories/transition_precondition_repository.dart';

/// The state emitted by
/// [TransitionPreconditionConfigCubit](transition_precondition_config_cubit.dart).
/// Added for `AIO-1936`.
sealed class TransitionPreconditionConfigState extends Equatable {
  const TransitionPreconditionConfigState();

  @override
  List<Object?> get props => [];
}

/// Initial state, before [TransitionPreconditionConfigCubit.load]
/// resolves.
class TransitionPreconditionConfigInitial
    extends TransitionPreconditionConfigState {
  /// Creates a [TransitionPreconditionConfigInitial] state.
  const TransitionPreconditionConfigInitial();
}

/// Loaded — carries the [SddStage] currently being edited, its
/// [TransitionGraph], and every [TransitionNode] reachable from that
/// graph's root, keyed by id. `SddStagePreconditionEditorScreen`'s canvas
/// and outline panes both render from this one state and call the same
/// [TransitionPreconditionConfigCubit] methods, so the two panes can never
/// diverge. Mirrors `DecisionGraphConfigLoaded`'s exact shape.
class TransitionPreconditionConfigLoaded
    extends TransitionPreconditionConfigState {
  /// Creates a [TransitionPreconditionConfigLoaded] state.
  const TransitionPreconditionConfigLoaded({
    required this.stage,
    required this.graph,
    required this.nodesById,
  });

  /// Which [SddStage] this state is editing.
  final SddStage stage;

  /// The currently-configured [TransitionGraph] for [stage].
  final TransitionGraph graph;

  /// Every [TransitionNode] reachable from [graph]'s root, keyed by
  /// [TransitionNode.id].
  final Map<String, TransitionNode> nodesById;

  @override
  List<Object?> get props => [stage, graph, nodesById];
}

/// An attempted [TransitionPreconditionConfigCubit] write was rejected — a
/// strict-tree-invariant violation. Carries [previous] (the last
/// known-good [TransitionPreconditionConfigLoaded] state) so the editor
/// never loses its tree while showing the rejection [message]. Unlike
/// `DecisionGraphConfigError`'s classified `reason` enum (resolved to
/// display text by a separate widget-layer function), this carries an
/// already-built [message] directly — a deliberate simplification for
/// this smaller, parallel engine (see proposal.md's "Why parallel types,
/// not shared ones").
class TransitionPreconditionConfigError
    extends TransitionPreconditionConfigState {
  /// Creates a [TransitionPreconditionConfigError] state.
  const TransitionPreconditionConfigError({
    required this.message,
    required this.previous,
  });

  /// Why the attempted write was rejected.
  final String message;

  /// The last successfully loaded state, preserved so the editor keeps
  /// rendering the tree unchanged alongside the error.
  final TransitionPreconditionConfigLoaded previous;

  @override
  List<Object?> get props => [message, previous];
}
