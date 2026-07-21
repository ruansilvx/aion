// design_system/molecules/complexity_meter.dart — ComplexityMeter widget (design-system layer).

import 'package:flutter/widgets.dart';

import 'package:aion/design_system/tokens/theme_scope.dart';
import 'package:aion/features/tickets/domain/enums/ticket_complexity.dart';

/// A small 3-bar ascending meter rendering [complexity] as a size
/// progression (1/2/3 bars filled for small/medium/large) rather than an
/// arbitrary color — used by the Complexity picker's trigger and menu
/// rows (`CreateTicketScreen`, `TicketDetailScreen`). Deliberately
/// monochrome (`primary`/`borderStrong`), never a priority hue, since
/// complexity is a neutral, non-priority dimension distinct from
/// `PriorityBadge`'s colored scale. Per
/// `aion-arch/changes/sdd-ticket-execution/design.md` §1.1.
class ComplexityMeter extends StatelessWidget {
  /// Creates a [ComplexityMeter] for [complexity]. `null` renders all
  /// three bars empty — used by the picker trigger's unset state.
  const ComplexityMeter({super.key, required this.complexity});

  /// Which complexity level to render, or `null` for "unset" (all bars
  /// empty).
  final TicketComplexity? complexity;

  static const _barHeights = [5.0, 8.5, 12.0];

  int get _filledCount => switch (complexity) {
    null => 0,
    TicketComplexity.small => 1,
    TicketComplexity.medium => 2,
    TicketComplexity.large => 3,
  };

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return SizedBox(
      width: 14,
      height: 12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            DecoratedBox(
              decoration: BoxDecoration(
                color: i < _filledCount ? c.primary : c.borderStrong,
                borderRadius: BorderRadius.circular(1),
              ),
              child: SizedBox(width: 3, height: _barHeights[i]),
            ),
          ],
        ],
      ),
    );
  }
}
