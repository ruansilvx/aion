// design_system/molecules/type_chip.dart — TypeChip widget + ticketTypeLabel helper (design-system layer).

import 'package:flutter/widgets.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// Returns the display label for [type] (e.g. `"Story"`). Single
/// one-place-mapping for every screen that renders a ticket type as text
/// (dropdowns, [TypeChip], parent pickers).
String ticketTypeLabel(BuildContext context, TicketType type) {
  final l10n = context.l10n;
  return switch (type) {
    TicketType.epic => l10n.ticketTypeEpic,
    TicketType.story => l10n.ticketTypeStory,
    TicketType.task => l10n.ticketTypeTask,
    TicketType.resource => l10n.ticketTypeResource,
    TicketType.page => l10n.ticketTypePage,
    TicketType.chat => l10n.ticketTypeChat,
    TicketType.signal => l10n.ticketTypeSignal,
    TicketType.release => l10n.ticketTypeRelease,
  };
}

/// A small square swatch + uppercase label showing a ticket's [type],
/// colored by that type's `AionColors` accent (`typeTask`/`typeStory`/
/// `typeEpic`/`typeResource`/`typePage`/`typeSignal`/`typeRelease`).
/// Promoted from `tickets_list_screen
/// .dart` (per `project.md`'s Pattern 2) so `features/pages/` can render the
/// same "PAGE" chip `TicketDetailScreen` renders for other types, without a
/// direct `features/tickets` presentation-layer import. Per
/// `aion-arch/changes/page-content-markdown-editor/design.md` §0.1, §3.1.
class TypeChip extends StatelessWidget {
  /// Creates a [TypeChip] for [type].
  const TypeChip({super.key, required this.type, this.isRow = true});

  /// The ticket type to render.
  final TicketType type;

  /// Whether to use the compact ticket-row sizing (`true`, default) or the
  /// larger ticket-detail sizing (`false`).
  final bool isRow;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final typeColor = switch (type) {
      TicketType.story => c.typeStory,
      TicketType.epic => c.typeEpic,
      TicketType.resource => c.typeResource,
      TicketType.page => c.typePage,
      TicketType.signal => c.typeSignal,
      TicketType.release => c.typeRelease,
      _ => c.typeTask,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: typeColor.withValues(alpha: t.fillAlpha),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: isRow
            ? const EdgeInsets.fromLTRB(5, 2, 7, 2)
            : const EdgeInsets.fromLTRB(6, 3, 8, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: typeColor,
                borderRadius: BorderRadius.circular(2),
              ),
              child: SizedBox(width: isRow ? 9 : 11, height: isRow ? 9 : 11),
            ),
            const SizedBox(width: 5),
            Text(
              ticketTypeLabel(context, type).toUpperCase(),
              style: AionText.chip.copyWith(color: typeColor),
            ),
          ],
        ),
      ),
    );
  }
}
