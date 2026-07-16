// presentation/widgets/trashed_ticket_tile.dart — A single row in TrashScreen's list (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_list_screen.dart'
    show TypeChip;

/// A single row in [TrashScreen]'s list. Deliberately simpler than a live
/// [TicketListTile] row — no status indicator and no priority badge,
/// since trashed tickets carry no workflow context. Non-navigating (no
/// detail screen for trashed tickets); offers Restore (neutral, no
/// confirmation) and Permanently Delete (danger, confirmed) actions.
class TrashedTicketTile extends StatelessWidget {
  /// Creates a [TrashedTicketTile] for [ticket]. [descendantCount] is how
  /// many other trashed tickets are in its structural subtree — shown as
  /// "+N subtasks" when greater than zero, omitted otherwise.
  const TrashedTicketTile({
    super.key,
    required this.ticket,
    required this.descendantCount,
    required this.onRestore,
    required this.onPermanentlyDelete,
  });

  /// The trashed ticket this row represents.
  final Ticket ticket;

  /// How many other trashed tickets are in [ticket]'s structural subtree.
  final int descendantCount;

  /// Called when the Restore action is tapped.
  final VoidCallback onRestore;

  /// Called when the Permanently Delete action is tapped (after its own
  /// confirm dialog resolves `true`).
  final VoidCallback onPermanentlyDelete;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.surfaceHover,
                          borderRadius: BorderRadius.all(AionRadius.sm),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            ticket.ticketId,
                            style: AionText.key.copyWith(
                              color: c.textSecondary,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Flexible(
                        child: Text(
                          ticket.title,
                          style: AionText.cardTitle.copyWith(
                            color: c.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AionSpacing.sp8),
                  Row(
                    children: [
                      TypeChip(type: ticket.type),
                      if (descendantCount > 0) ...[
                        const SizedBox(width: 9),
                        Text(
                          '+$descendantCount subtasks',
                          style: AionText.time.copyWith(color: c.textMuted),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AionSpacing.sp12),
            _RestoreAction(onTap: onRestore),
            const SizedBox(width: AionSpacing.sp8),
            _PermanentDeleteAction(onTap: onPermanentlyDelete),
          ],
        ),
      ),
    );
  }
}

/// [TrashedTicketTile]'s neutral Restore action: `34×34`, no confirmation.
class _RestoreAction extends StatefulWidget {
  const _RestoreAction({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_RestoreAction> createState() => _RestoreActionState();
}

class _RestoreActionState extends State<_RestoreAction> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final boxShadow = _isFocused
        ? [
            BoxShadow(
              color: c.primary.withValues(alpha: t.isDark ? 0.30 : 0.16),
              spreadRadius: 3,
            ),
          ]
        : const <BoxShadow>[];

    return Semantics(
      button: true,
      label: context.l10n.ticketTrashRestoreAction,
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
          onShowFocusHighlight: (value) =>
              setState(() => _isFocused = value),
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
                  boxShadow: boxShadow,
                ),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: PhosphorIcon(
                      PhosphorIcons.arrowUUpLeftLight,
                      size: 16,
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

/// [TrashedTicketTile]'s danger Permanently Delete action: `34×34`, opens
/// a confirm dialog via [onTap].
class _PermanentDeleteAction extends StatefulWidget {
  const _PermanentDeleteAction({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_PermanentDeleteAction> createState() =>
      _PermanentDeleteActionState();
}

class _PermanentDeleteActionState extends State<_PermanentDeleteAction> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final fillAlpha = t.isDark ? fillAlphaObsidian : fillAlphaArctic;

    final boxShadow = _isFocused
        ? [
            BoxShadow(
              color: c.danger.withValues(alpha: t.isDark ? 0.30 : 0.16),
              spreadRadius: 3,
            ),
          ]
        : const <BoxShadow>[];

    return Semantics(
      button: true,
      label: context.l10n.ticketTrashPermanentDeleteAction,
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
          onShowFocusHighlight: (value) =>
              setState(() => _isFocused = value),
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
                  color: c.danger.withValues(
                    alpha: _isHovered ? fillAlpha + 0.06 : fillAlpha,
                  ),
                  borderRadius: BorderRadius.all(AionRadius.md),
                  boxShadow: boxShadow,
                ),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: PhosphorIcon(
                      PhosphorIcons.trashLight,
                      size: 15,
                      color: c.danger,
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
