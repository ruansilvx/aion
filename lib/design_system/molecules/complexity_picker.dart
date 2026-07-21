// design_system/molecules/complexity_picker.dart — ComplexityPicker widget (design-system layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/localization/context_localizations_x.dart';
import 'package:aion/design_system/molecules/complexity_meter.dart';
import 'package:aion/design_system/molecules/selection_menu.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';
import 'package:aion/features/tickets/domain/enums/ticket_complexity.dart';

/// A labeled, full-width `TicketComplexity?` picker for
/// `CreateTicketScreen`'s create form, mirroring `AppDropdown`'s visual
/// shape (label above, bordered trigger box below). Built on
/// [SelectionMenu] rather than `AppDropdown` because complexity is
/// genuinely optional with no "unset" sentinel value (unlike
/// `TicketPriority.none`) — `AppDropdown.value` is non-nullable and
/// can't represent that. Per
/// `aion-arch/changes/sdd-ticket-execution/design.md` §1.
class ComplexityPicker extends StatelessWidget {
  /// Creates a [ComplexityPicker] showing [labelText] above a trigger
  /// reflecting [value], calling [onSelected] when the user picks a new
  /// value.
  const ComplexityPicker({
    super.key,
    required this.labelText,
    required this.value,
    required this.onSelected,
    required this.semanticsLabel,
    this.focusNode,
  });

  /// Label rendered above the field.
  final String labelText;

  /// The currently selected complexity, or `null` if unset.
  final TicketComplexity? value;

  /// Called with the newly selected value.
  final ValueChanged<TicketComplexity?> onSelected;

  /// Accessibility label describing what this menu changes.
  final String semanticsLabel;

  /// Optional focus node for keyboard/tab navigation.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AionSpacing.sp4),
          child: Text(
            labelText,
            style: AionText.label.copyWith(color: c.textSecondary),
          ),
        ),
        SelectionMenu<TicketComplexity?>(
          semanticsLabel: semanticsLabel,
          items: const [null, ...TicketComplexity.values],
          currentValue: value,
          onSelected: onSelected,
          itemLabel: (v) => v == null
              ? context.l10n.commonNotSet
              : ticketComplexityLabel(context, v),
          itemBuilder: (context, c, item) => ComplexityMenuRow(item: item),
          trigger: FocusableActionDetector(
            focusNode: focusNode,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.all(AionRadius.lg),
                border: Border.all(color: c.border, width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    if (value != null) ...[
                      ComplexityMeter(complexity: value),
                      const SizedBox(width: 9),
                    ],
                    Expanded(
                      child: Text(
                        value == null
                            ? context.l10n.createTicketComplexityHint
                            : ticketComplexityLabel(context, value!),
                        style: AionText.bodySm.copyWith(
                          color: value == null ? c.textMuted : c.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    PhosphorIcon(
                      PhosphorIcons.caretDownLight,
                      size: 12,
                      color: c.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Localized display label for [complexity]. Kept alongside
/// [ComplexityPicker] since it's the sole consumer today, mirroring
/// `ticketPriorityLabel`/`ticketTypeLabel`'s placement pattern.
String ticketComplexityLabel(
  BuildContext context,
  TicketComplexity complexity,
) {
  final l10n = context.l10n;
  return switch (complexity) {
    TicketComplexity.small => l10n.ticketComplexitySmall,
    TicketComplexity.medium => l10n.ticketComplexityMedium,
    TicketComplexity.large => l10n.ticketComplexityLarge,
  };
}

/// A one-word scale hint for [complexity] (`"~1 file"` / `"a few files"` /
/// `"multi-module"`), shown as a [ComplexityMenuRow]'s trailing sub-hint.
/// Per design.md §1.4.
String ticketComplexitySubHint(
  BuildContext context,
  TicketComplexity complexity,
) {
  final l10n = context.l10n;
  return switch (complexity) {
    TicketComplexity.small => l10n.ticketComplexitySubHintSmall,
    TicketComplexity.medium => l10n.ticketComplexitySubHintMedium,
    TicketComplexity.large => l10n.ticketComplexitySubHintLarge,
  };
}

/// One [SelectionMenu]`<TicketComplexity?>` menu row: the complexity
/// meter, the label, and — for a non-`null` [item] — a trailing
/// scale-hint sub-label. Public (not folded into [ComplexityPicker])
/// since `TicketDetailScreen`'s inline
/// `SelectionMenu<TicketComplexity?>` (the ticket-meta row's complexity
/// field) reuses it too. Per design.md §1.4.
class ComplexityMenuRow extends StatelessWidget {
  /// Creates a [ComplexityMenuRow] for [item] (`null` renders the
  /// "unset" label with no meter/sub-hint).
  const ComplexityMenuRow({super.key, required this.item});

  /// The complexity this row represents, or `null` for "unset".
  final TicketComplexity? item;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final item = this.item;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ComplexityMeter(complexity: item),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            item == null
                ? context.l10n.commonNotSet
                : ticketComplexityLabel(context, item),
            style: AionText.bodySm.copyWith(
              color: c.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (item != null) ...[
          const SizedBox(width: 8),
          Text(
            ticketComplexitySubHint(context, item),
            style: AionText.time.copyWith(color: c.textMuted),
          ),
        ],
      ],
    );
  }
}
