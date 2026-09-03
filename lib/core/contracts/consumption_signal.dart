// core/contracts/consumption_signal.dart — ConsumptionSignal sealed hierarchy (core layer).

import 'package:equatable/equatable.dart';

/// The one generic "consumption" dimension every provider's own budget/ usage
/// signal maps onto, via `AgentProvider.describeOverage`. Replaces the bare
/// `VoidCallback` overage signal `ChatCubit.runChatTurn` used to expose. See
/// `AIO-1544` §1, §4.
sealed class ConsumptionSignal extends Equatable {
  /// Creates a [ConsumptionSignal] carrying a human-readable [message].
  const ConsumptionSignal(this.message);

  /// A human-readable description of the consumption signal.
  final String message;
}

/// A flat-rate plan's usage-window signal (e.g. Claude Pro/Max's opt-in
/// overage prompt). No numeric fraction — the provider that emits this
/// can't report one.
class UsageWindowConsumption extends ConsumptionSignal {
  /// Creates a [UsageWindowConsumption] carrying [message].
  const UsageWindowConsumption(super.message);

  @override
  List<Object?> get props => [message];
}

/// A token-billed provider's cost signal. [amountUsd] is `null` when the
/// provider can report the signal occurred but not an exact amount.
class CostConsumption extends ConsumptionSignal {
  /// Creates a [CostConsumption] carrying [message] and [amountUsd].
  const CostConsumption(super.message, this.amountUsd);

  /// The signaled cost in US dollars, or `null` if unknown.
  final double? amountUsd;

  @override
  List<Object?> get props => [message, amountUsd];
}
