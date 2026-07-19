// design_system/molecules/delete_action_button.dart — DeleteActionButton widget (design-system layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/design_system/molecules/app_confirm_dialog.dart';
import 'package:aion/design_system/tokens/aion_colors.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';

/// A minimal, generic destructive-action trigger for a screen header: a
/// trash icon-button that opens [showAppConfirmDialog] and, on
/// confirmation, calls [onConfirmed]. Carries no `Ticket`/feature
/// awareness — the caller supplies the confirmation copy and the delete
/// action itself, so this widget stays reusable by any screen (e.g.
/// `PageDetailScreen`) without depending on `TicketsCubit`. Promoted from
/// `TicketOverflowMenu`'s "Delete ticket" row (per `project.md`'s
/// Pattern 2) — `TicketOverflowMenu` itself is left untouched in
/// `features/tickets`, since it reads `TicketsCubit` directly and isn't
/// generic. Per
/// `aion-arch/changes/page-content-markdown-editor/design.md` §7.
class DeleteActionButton extends StatefulWidget {
  /// Creates a [DeleteActionButton].
  const DeleteActionButton({
    super.key,
    required this.semanticsLabel,
    required this.confirmTitle,
    required this.confirmMessage,
    required this.confirmLabel,
    required this.onConfirmed,
    this.isDisabled = false,
  });

  /// Accessibility label for the trigger icon-button.
  final String semanticsLabel;

  /// Confirmation dialog title.
  final String confirmTitle;

  /// Confirmation dialog body message.
  final String confirmMessage;

  /// Confirmation dialog's confirm-button label.
  final String confirmLabel;

  /// Called once the user confirms the delete.
  final VoidCallback onConfirmed;

  /// Disables the trigger (e.g. while a delete is already in flight).
  final bool isDisabled;

  @override
  State<DeleteActionButton> createState() => _DeleteActionButtonState();
}

class _DeleteActionButtonState extends State<DeleteActionButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  Future<void> _onPressed() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: widget.confirmTitle,
      message: widget.confirmMessage,
      confirmLabel: widget.confirmLabel,
      tone: ConfirmDialogTone.reversible,
    );
    if (confirmed && mounted) widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isHoverStyled = _isHovered && !widget.isDisabled;

    final fill = _isPressed
        ? c.danger.withValues(alpha: t.isDark ? 0.26 : 0.20)
        : isHoverStyled
        ? c.destructiveTint(t.isDark)
        : const Color(0x00000000);
    final glyphColor = isHoverStyled || _isPressed ? c.danger : c.textSecondary;

    return Opacity(
      opacity: widget.isDisabled ? 0.45 : 1.0,
      child: Semantics(
        button: true,
        label: widget.semanticsLabel,
        child: MouseRegion(
          cursor: widget.isDisabled
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.isDisabled ? null : _onPressed,
            onTapDown: widget.isDisabled
                ? null
                : (_) => setState(() => _isPressed = true),
            onTapUp: widget.isDisabled
                ? null
                : (_) => setState(() => _isPressed = false),
            onTapCancel: widget.isDisabled
                ? null
                : () => setState(() => _isPressed = false),
            child: AnimatedScale(
              scale: _isPressed ? 0.98 : 1.0,
              duration: const Duration(milliseconds: 80),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: fill,
                  border: Border.all(color: c.border, width: 1),
                  borderRadius: const BorderRadius.all(AionRadius.iconBtn),
                ),
                child: SizedBox(
                  width: 37,
                  height: 37,
                  child: Center(
                    child: PhosphorIcon(
                      PhosphorIcons.trashLight,
                      size: 20,
                      color: glyphColor,
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
