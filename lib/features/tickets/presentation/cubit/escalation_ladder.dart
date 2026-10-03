// presentation/cubit/escalation_ladder.dart — Per-Task model-escalation state machine for coding execution (presentation layer).

import 'package:aion/features/providers/domain/enums/model_phase.dart';

/// One rung of the coding-execution escalation ladder (`AIO-3057`). A run
/// starts on [execution]; repeated self-verify failures climb it.
enum ExecutionRung {
  /// The configured [ModelPhase.execution] model — every run's first rung.
  execution,

  /// The configured [ModelPhase.capable] model, running the same implement and
  /// self-verify turns [execution] would.
  capable,

  /// A read-only [ModelPhase.frontier] review of the Task description and its
  /// plan source. Not an implement rung: no implement turn ever runs on it.
  planCheck,

  /// A single last [ModelPhase.execution] attempt, run only after the plan
  /// check rewrote the Task description.
  finalExecution,
}

/// What a caller must do after [EscalationLadder.onSelfVerifyFailed].
enum LadderStep {
  /// Stay on the current rung and retry (the rung's failure budget is not yet
  /// spent).
  retrySameRung,

  /// The ladder moved to a stronger implement rung — read
  /// [EscalationLadder.rung] for which, and retry on it.
  escalate,

  /// Every implement rung that could help is spent — run the Frontier plan
  /// check ([ExecutionRung.planCheck]).
  runPlanCheck,

  /// The ladder is exhausted — stop and hand the Task to a human.
  giveUp,
}

/// One self-verify failure the ladder counted, kept for the human-facing lead
/// report.
class LadderFailure {
  /// Creates a [LadderFailure] recorded on [rung] with [reason].
  const LadderFailure(this.rung, this.reason);

  /// The rung the failing attempt ran on.
  final ExecutionRung rung;

  /// The self-verify failure reason the model reported.
  final String reason;
}

/// Per-Task state machine for the coding-execution escalation ladder
/// (`AIO-3057`): Execution → Capable → Frontier plan check → one final
/// Execution attempt → human. Pure Dart — no cubit, repository or model
/// access — so `TicketsCubit` only asks it what to do next and then performs
/// that.
///
/// Only a self-verify failure counts: [onSelfVerifyFailed] is the only
/// method that moves it, and a mechanical-check mismatch or a task-verify
/// `NEEDS FIXES` is simply never reported here, so those neither count toward
/// a rung's budget nor reset it. [threshold] consecutive counted failures on
/// the current rung spend that rung. A rung whose model would not change
/// (collapsed tiers) or whose provider cannot run coding execution is skipped
/// via [capableUsable].
class EscalationLadder {
  /// Creates a ladder starting at [startRung] with [startFailures] counted
  /// failures already on it (a gated run resumed from its persisted marker —
  /// see [stateMarker]). [capableUsable] says whether
  /// [ExecutionRung.capable] is worth climbing to: its model differs from the
  /// Execution model and its provider supports full tool access.
  EscalationLadder({
    required this.capableUsable,
    this.planCheckAvailable = true,
    this.threshold = 2,
    ExecutionRung startRung = ExecutionRung.execution,
    int startFailures = 0,
  }) : _rung = startRung,
       _failuresOnRung = startFailures;

  /// Whether [ExecutionRung.capable] is a real escalation target.
  final bool capableUsable;

  /// Whether the run can actually perform the Frontier plan check. When
  /// `false`, spending the last implement rung returns [LadderStep.giveUp]
  /// and leaves [rung] where it is, so the caller keeps its pre-ladder retry
  /// behaviour instead of stopping early.
  final bool planCheckAvailable;

  /// Counted self-verify failures that spend an implement rung.
  final int threshold;

  ExecutionRung _rung;
  int _failuresOnRung;
  final List<LadderFailure> _trail = [];

  /// The rung the next implement (or plan-check) turn runs on.
  ExecutionRung get rung => _rung;

  /// Counted self-verify failures on the current rung.
  int get failuresOnRung => _failuresOnRung;

  /// Every counted failure so far this run, oldest first.
  List<LadderFailure> get trail => List.unmodifiable(_trail);

  /// The [ModelPhase] the next implement and self-verify turns must resolve
  /// their model from. [ExecutionRung.planCheck] never runs an implement turn;
  /// it reports [ModelPhase.frontier] for symmetry.
  ModelPhase get implementPhase => switch (_rung) {
    ExecutionRung.execution ||
    ExecutionRung.finalExecution => ModelPhase.execution,
    ExecutionRung.capable => ModelPhase.capable,
    ExecutionRung.planCheck => ModelPhase.frontier,
  };

  /// Records one self-verify failure with [reason] on the current rung and
  /// returns what to do next. May move [rung].
  LadderStep onSelfVerifyFailed(String reason) {
    _trail.add(LadderFailure(_rung, reason));
    _failuresOnRung += 1;
    switch (_rung) {
      case ExecutionRung.execution:
        if (_failuresOnRung < threshold) return LadderStep.retrySameRung;
        if (capableUsable) {
          _moveTo(ExecutionRung.capable);
          return LadderStep.escalate;
        }
        return _spent();
      case ExecutionRung.capable:
        if (_failuresOnRung < threshold) return LadderStep.retrySameRung;
        return _spent();
      case ExecutionRung.finalExecution:
        return LadderStep.giveUp;
      case ExecutionRung.planCheck:
        // The plan check is not an implement rung; a caller reporting an
        // implement failure here has lost track of the ladder.
        return LadderStep.giveUp;
    }
  }

  /// Moves from [ExecutionRung.planCheck] to [ExecutionRung.finalExecution]
  /// once the plan check rewrote the Task description.
  void onPlanRewritten() => _moveTo(ExecutionRung.finalExecution);

  LadderStep _spent() {
    if (!planCheckAvailable) return LadderStep.giveUp;
    _moveTo(ExecutionRung.planCheck);
    return LadderStep.runPlanCheck;
  }

  void _moveTo(ExecutionRung next) {
    _rung = next;
    _failuresOnRung = 0;
  }

  /// A machine-readable line to append to a stop comment so a resumed run can
  /// restore this ladder (`[ladder: rung=capable failures=1]`), or `null` when
  /// the ladder is untouched (still on [ExecutionRung.execution] with no
  /// failures) or no longer resumable (past the implement rungs).
  String? get stateMarker {
    if (_rung != ExecutionRung.execution && _rung != ExecutionRung.capable) {
      return null;
    }
    if (_rung == ExecutionRung.execution && _failuresOnRung == 0) return null;
    return '[ladder: rung=${_rung.name} failures=$_failuresOnRung]';
  }

  static final _markerPattern = RegExp(
    r'\[ladder: rung=(execution|capable) failures=(\d+)\]\s*$',
  );

  /// [comment] without its trailing [stateMarker] line, for showing a stop
  /// comment to the user — the marker is machine-readable resume state, not
  /// part of the failure message.
  static String stripMarker(String comment) =>
      comment.replaceFirst(RegExp(r'\s*\[ladder: [^\]]*\]\s*$'), '');

  /// Restores a ladder from [lastComment], the execution chat's most recent
  /// comment, if it ends with a [stateMarker] line; otherwise a fresh ladder
  /// on [ExecutionRung.execution]. A restored [ExecutionRung.capable] falls
  /// back to a fresh ladder when [capableUsable] is `false` (settings changed
  /// since the marker was written).
  factory EscalationLadder.resume({
    required bool capableUsable,
    bool planCheckAvailable = true,
    String? lastComment,
    int threshold = 2,
  }) {
    final match = lastComment == null
        ? null
        : _markerPattern.firstMatch(lastComment);
    if (match == null) {
      return EscalationLadder(
        capableUsable: capableUsable,
        planCheckAvailable: planCheckAvailable,
        threshold: threshold,
      );
    }
    final rung = ExecutionRung.values.byName(match.group(1)!);
    if (rung == ExecutionRung.capable && !capableUsable) {
      return EscalationLadder(
        capableUsable: capableUsable,
        planCheckAvailable: planCheckAvailable,
        threshold: threshold,
      );
    }
    return EscalationLadder(
      capableUsable: capableUsable,
      planCheckAvailable: planCheckAvailable,
      threshold: threshold,
      startRung: rung,
      startFailures: int.parse(match.group(2)!),
    );
  }
}
