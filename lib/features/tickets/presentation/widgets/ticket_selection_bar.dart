// presentation/widgets/ticket_selection_bar.dart — Bulk-delete contextual bar (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';

/// The contextual bar shown in place of the create-ticket FAB while
/// `TicketsListScreen`'s selection mode is active: a Cancel/exit control,
/// the selected count, a select-all/deselect-all toggle, and a destructive
/// Delete action that trashes the whole selection.
class TicketSelectionBar extends StatelessWidget {
  /// Creates a [TicketSelectionBar].
  const TicketSelectionBar({
    super.key,
    required this.selectedCount,
    required this.allSelected,
    required this.onCancel,
    required this.onSelectAll,
    required this.onDelete,
  });

  /// How many tickets are currently selected.
  final int selectedCount;

  /// Whether every currently visible/filtered ticket is selected — drives
  /// the select-all toggle's label ("Select all" vs. "Deselect all").
  final bool allSelected;

  /// Called when the Cancel/exit control is tapped.
  final VoidCallback onCancel;

  /// Called when the select-all/deselect-all toggle is tapped.
  final VoidCallback onSelectAll;

  /// Called when the Delete button is tapped. Only reachable when
  /// [selectedCount] is greater than zero — the button renders disabled
  /// otherwise.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border, width: 1),
        borderRadius: BorderRadius.all(AionRadius.xl),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF000000,
            ).withValues(alpha: t.isDark ? 0.55 : 0.30),
            offset: const Offset(0, 18),
            blurRadius: 40,
            spreadRadius: -14,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _CancelControl(onTap: onCancel),
            const SizedBox(width: 10),
            Text(
              context.l10n.ticketSelectionCountLabel(selectedCount),
              style: AionText.button.copyWith(
                fontSize: 13.5,
                color: selectedCount > 0 ? c.textPrimary : c.textMuted,
              ),
            ),
            const Spacer(),
            AppButton(
              label: allSelected
                  ? context.l10n.ticketSelectionDeselectAllAction
                  : context.l10n.ticketSelectionSelectAllAction,
              variant: AppButtonVariant.ghost,
              onPressed: onSelectAll,
            ),
            AppButton(
              label: context.l10n.ticketSelectionDeleteAction,
              variant: AppButtonVariant.destructive,
              icon: PhosphorIcons.trashLight,
              onPressed: selectedCount > 0 ? onDelete : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// The bar's leading Cancel/exit control: a small `34×34` square icon
/// button.
class _CancelControl extends StatefulWidget {
  const _CancelControl({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_CancelControl> createState() => _CancelControlState();
}

class _CancelControlState extends State<_CancelControl> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Semantics(
      button: true,
      label: context.l10n.ticketSelectionExitLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: FocusableActionDetector(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: AnimatedScale(
              scale: _isPressed ? 0.96 : 1.0,
              duration: const Duration(milliseconds: 80),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surfaceHover,
                  borderRadius: BorderRadius.all(AionRadius.md),
                ),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: PhosphorIcon(
                      PhosphorIcons.xLight,
                      size: 17,
                      color: _isHovered ? c.textPrimary : c.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
