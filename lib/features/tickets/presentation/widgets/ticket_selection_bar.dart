// presentation/widgets/ticket_selection_bar.dart — Bulk-delete contextual bar (presentation layer).

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_board_view.dart'
    show ticketPriorityLabel, ticketStatusLabel;

/// Width below which [TicketSelectionBar]'s available space is
/// considered "compact" (phone-native) — the Status and Priority
/// triggers drop their text labels and render as icon-only 34×34 square
/// buttons, and the count label compacts to a bare number. See
/// design.md §1.7b.
const double _kBarCompactWidth = 360;

/// The contextual bar shown in place of the create-ticket FAB while
/// `TicketsListScreen`'s selection mode is active: a Cancel/exit control,
/// the selected count, a select-all/deselect-all toggle, Status/Priority
/// bulk-edit triggers, and a destructive Delete action that trashes the
/// whole selection.
class TicketSelectionBar extends StatelessWidget {
  /// Creates a [TicketSelectionBar].
  const TicketSelectionBar({
    super.key,
    required this.selectedCount,
    required this.allSelected,
    required this.onCancel,
    required this.onSelectAll,
    required this.onChangeStatus,
    required this.onChangePriority,
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

  /// Called with the chosen status when the Status action's overlay
  /// selects a value. Only reachable when [selectedCount] is greater than
  /// zero.
  final ValueChanged<TicketStatus> onChangeStatus;

  /// Called with the chosen priority when the Priority action's overlay
  /// selects a value. Only reachable when [selectedCount] is greater than
  /// zero.
  final ValueChanged<TicketPriority> onChangePriority;

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < _kBarCompactWidth;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _CancelControl(onTap: onCancel),
                const SizedBox(width: 10),
                Text(
                  compact
                      ? '$selectedCount'
                      : context.l10n.ticketSelectionCountLabel(
                          selectedCount,
                        ),
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
                const SizedBox(width: 10),
                _BulkStatusPriorityGroup(
                  selectedCount: selectedCount,
                  compact: compact,
                  onChangeStatus: onChangeStatus,
                  onChangePriority: onChangePriority,
                ),
                const SizedBox(width: 10),
                AppButton(
                  label: context.l10n.ticketSelectionDeleteAction,
                  variant: AppButtonVariant.destructive,
                  icon: PhosphorIcons.trashLight,
                  onPressed: selectedCount > 0 ? onDelete : null,
                ),
              ],
            );
          },
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

/// A silent (no visible confirmation) intent to dismiss an open bulk
/// overlay (`BulkStatusMenu`/`BulkPriorityMenu`) without applying a
/// selection — bound to `Escape` on each overlay's panel.
class _DismissIntent extends Intent {
  const _DismissIntent();
}

/// Coordinates [TicketSelectionBar]'s Status and Priority triggers so
/// only one of their overlays ([BulkStatusMenu]/[BulkPriorityMenu]) is
/// open at a time — opening one closes the other, per design.md §5.5.
/// Owns each trigger's [LayerLink] and [OverlayEntry] lifecycle; the
/// triggers themselves ([_BulkTrigger]) are stateless about overlay
/// mechanics and only render visual state handed to them.
class _BulkStatusPriorityGroup extends StatefulWidget {
  const _BulkStatusPriorityGroup({
    required this.selectedCount,
    required this.compact,
    required this.onChangeStatus,
    required this.onChangePriority,
  });

  final int selectedCount;
  final bool compact;
  final ValueChanged<TicketStatus> onChangeStatus;
  final ValueChanged<TicketPriority> onChangePriority;

  @override
  State<_BulkStatusPriorityGroup> createState() =>
      _BulkStatusPriorityGroupState();
}

class _BulkStatusPriorityGroupState extends State<_BulkStatusPriorityGroup> {
  final LayerLink _statusLink = LayerLink();
  final LayerLink _priorityLink = LayerLink();
  final GlobalKey _statusKey = GlobalKey();
  final GlobalKey _priorityKey = GlobalKey();
  OverlayEntry? _statusEntry;
  OverlayEntry? _priorityEntry;

  /// Rough panel-height estimate used only to decide whether an overlay
  /// would clip the top of the viewport if opened upward — 6 rows × 36
  /// plus the panel's own vertical padding/border.
  static const double _kStatusMenuHeight = 234;

  /// Same rationale as [_kStatusMenuHeight], for [BulkPriorityMenu]'s 5
  /// rows.
  static const double _kPriorityMenuHeight = 198;

  @override
  void dispose() {
    _statusEntry?.remove();
    _priorityEntry?.remove();
    super.dispose();
  }

  bool _openUpward(GlobalKey key, double estimatedHeight) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return true;
    final topLeft = box.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final spaceAbove = topLeft.dy;
    final spaceBelow = screenHeight - topLeft.dy - box.size.height;
    if (spaceAbove < estimatedHeight && spaceBelow > spaceAbove) return false;
    return true;
  }

  void _closeStatus() {
    _statusEntry?.remove();
    _statusEntry = null;
    if (mounted) setState(() {});
  }

  void _closePriority() {
    _priorityEntry?.remove();
    _priorityEntry = null;
    if (mounted) setState(() {});
  }

  void _toggleStatus() {
    if (_statusEntry != null) {
      _closeStatus();
      return;
    }
    _closePriority();
    final upward = _openUpward(_statusKey, _kStatusMenuHeight);
    final overlay = Overlay.of(context);
    _statusEntry = OverlayEntry(
      builder: (_) => BulkStatusMenu(
        layerLink: _statusLink,
        openUpward: upward,
        onSelected: (status) {
          widget.onChangeStatus(status);
          _closeStatus();
        },
        onDismiss: _closeStatus,
      ),
    );
    overlay.insert(_statusEntry!);
    setState(() {});
  }

  void _togglePriority() {
    if (_priorityEntry != null) {
      _closePriority();
      return;
    }
    _closeStatus();
    final upward = _openUpward(_priorityKey, _kPriorityMenuHeight);
    final overlay = Overlay.of(context);
    _priorityEntry = OverlayEntry(
      builder: (_) => BulkPriorityMenu(
        layerLink: _priorityLink,
        openUpward: upward,
        onSelected: (priority) {
          widget.onChangePriority(priority);
          _closePriority();
        },
        onDismiss: _closePriority,
      ),
    );
    overlay.insert(_priorityEntry!);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.selectedCount > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CompositedTransformTarget(
          link: _statusLink,
          child: KeyedSubtree(
            key: _statusKey,
            child: _BulkTrigger(
              label: context.l10n.ticketSelectionStatusAction,
              iconPainter: _SwapIconPainter.new,
              enabled: enabled,
              isOpen: _statusEntry != null,
              compact: widget.compact,
              onTap: _toggleStatus,
              semanticsLabel: context.l10n.ticketSelectionStatusAction,
            ),
          ),
        ),
        const SizedBox(width: 10),
        CompositedTransformTarget(
          link: _priorityLink,
          child: KeyedSubtree(
            key: _priorityKey,
            child: _BulkTrigger(
              label: context.l10n.ticketSelectionPriorityAction,
              iconPainter: _FlagIconPainter.new,
              enabled: enabled,
              isOpen: _priorityEntry != null,
              compact: widget.compact,
              onTap: _togglePriority,
              semanticsLabel: context.l10n.ticketSelectionPriorityAction,
            ),
          ),
        ),
      ],
    );
  }
}

/// The Status/Priority action trigger: `GestureDetector` → `Focus` →
/// `AnimatedContainer` (150ms) → `Row` (icon, gap, label), per design.md
/// §1.5/§1.6. Purely presentational — overlay open/close mechanics live
/// in [_BulkStatusPriorityGroupState]; this widget only reports taps via
/// [onTap] and renders whichever state [enabled]/[isOpen]/hover/focus/
/// press currently apply. Below [_kBarCompactWidth] ([compact] `true`),
/// renders as a 34×34 icon-only square instead of the icon+label pill.
class _BulkTrigger extends StatefulWidget {
  const _BulkTrigger({
    required this.label,
    required this.iconPainter,
    required this.enabled,
    required this.isOpen,
    required this.compact,
    required this.onTap,
    required this.semanticsLabel,
  });

  /// The trigger's text label ("Status"/"Priority") — hidden when
  /// [compact] is `true`.
  final String label;

  /// Builds the trigger's leading glyph painter for the given content
  /// color, so the icon always matches the trigger's current
  /// default/hover/focused/pressed/disabled state color.
  final CustomPainter Function(Color color) iconPainter;

  /// Whether the trigger is interactive — `false` when nothing is
  /// selected (§1.5.5).
  final bool enabled;

  /// Whether this trigger's own overlay is currently open — renders the
  /// persistent active state (§1.5.4) while `true`.
  final bool isOpen;

  /// Whether to render the icon-only 34×34 compact variant (§1.7b).
  final bool compact;

  /// Called on tap or `Enter`/`Space` activation. Not called when
  /// [enabled] is `false`.
  final VoidCallback onTap;

  /// Announced by `Semantics(button: true)`.
  final String semanticsLabel;

  @override
  State<_BulkTrigger> createState() => _BulkTriggerState();
}

class _BulkTriggerState extends State<_BulkTrigger> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final Color fill;
    final Color border;
    final Color content;
    var opacity = 1.0;
    List<BoxShadow>? ring;

    if (!widget.enabled) {
      fill = const Color(0x00000000);
      border = c.border;
      content = c.textMuted;
      opacity = 0.4;
    } else if (widget.isOpen) {
      // Persists while the overlay is open (§1.5.4) — deliberately covers
      // both "just tapped" and "open, pointer released" without a
      // separate transient pressed state.
      fill = c.primarySubtle;
      border = c.primary;
      content = c.primary;
    } else if (_isFocused) {
      fill = c.surfaceHover;
      border = c.border;
      content = c.textSecondary;
      ring = AionShadows.focus(c, t.isDark);
    } else if (_isHovered) {
      fill = c.surfaceHover;
      border = c.borderStrong;
      content = c.textPrimary;
    } else {
      fill = c.surfaceHover;
      border = c.border;
      content = c.textSecondary;
    }

    final iconSize = widget.compact ? 16.0 : 15.0;
    final icon = SizedBox(
      width: iconSize,
      height: iconSize,
      child: CustomPaint(painter: widget.iconPainter(content)),
    );

    final child = widget.compact
        ? Center(child: icon)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: AionText.button.copyWith(
                  fontSize: 12.5,
                  color: content,
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticsLabel,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: widget.enabled
            ? (_) => setState(() => _isHovered = true)
            : null,
        onExit: widget.enabled
            ? (_) => setState(() => _isHovered = false)
            : null,
        child: FocusableActionDetector(
          enabled: widget.enabled,
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
            onTap: widget.enabled ? widget.onTap : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: widget.compact ? 34 : null,
              height: widget.compact ? 34 : 32,
              padding: widget.compact
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: fill,
                border: Border.all(color: border, width: 1),
                borderRadius: BorderRadius.all(AionRadius.md),
                boxShadow: ring,
              ),
              child: Opacity(opacity: opacity, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the Status trigger's bidirectional swap-arrows glyph: two
/// vertical shafts, an arrow up on the left shaft and an arrow down on
/// the right shaft, stroke-only. Matches design.md §1.5's icon spec
/// (15×15, stroke 1.7, round caps/joins).
class _SwapIconPainter extends CustomPainter {
  /// Creates a [_SwapIconPainter] that strokes with [color].
  const _SwapIconPainter(this.color);

  /// The current trigger content color (matches its default/hover/
  /// focused/pressed/disabled state).
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final leftX = w * 0.32;
    final rightX = w * 0.68;

    canvas.drawLine(Offset(leftX, h * 0.85), Offset(leftX, h * 0.15), paint);
    final leftHead = Path()
      ..moveTo(leftX - w * 0.22, h * 0.4)
      ..lineTo(leftX, h * 0.15)
      ..lineTo(leftX + w * 0.22, h * 0.4);
    canvas.drawPath(leftHead, paint);

    canvas.drawLine(Offset(rightX, h * 0.15), Offset(rightX, h * 0.85), paint);
    final rightHead = Path()
      ..moveTo(rightX - w * 0.22, h * 0.6)
      ..lineTo(rightX, h * 0.85)
      ..lineTo(rightX + w * 0.22, h * 0.6);
    canvas.drawPath(rightHead, paint);
  }

  @override
  bool shouldRepaint(covariant _SwapIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Paints the Priority trigger's flag glyph: a vertical pole with a
/// pennant, stroke-only. Matches design.md §1.6's icon spec (15×15,
/// stroke 1.7).
class _FlagIconPainter extends CustomPainter {
  /// Creates a [_FlagIconPainter] that strokes with [color].
  const _FlagIconPainter(this.color);

  /// The current trigger content color (matches its default/hover/
  /// focused/pressed/disabled state).
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final poleX = w * 0.28;

    canvas.drawLine(Offset(poleX, h * 0.1), Offset(poleX, h * 0.9), paint);

    final pennant = Path()
      ..moveTo(poleX, h * 0.15)
      ..lineTo(w * 0.8, h * 0.32)
      ..lineTo(poleX, h * 0.5)
      ..close();
    canvas.drawPath(pennant, paint);
  }

  @override
  bool shouldRepaint(covariant _FlagIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A single selectable row inside [BulkStatusMenu]/[BulkPriorityMenu]:
/// `GestureDetector` → `Focus` → `AnimatedContainer` (100ms, `easeOut`) →
/// `Row` (leading indicator, gap, label). Shared by both menus per
/// design.md §4. No disabled/error state — every status/priority value is
/// always selectable (a bulk selection may span tickets with different
/// current values, so nothing is excluded).
class BulkOverlayRow extends StatefulWidget {
  /// Creates a [BulkOverlayRow].
  const BulkOverlayRow({
    super.key,
    required this.leading,
    required this.label,
    required this.onTap,
    required this.semanticsLabel,
    this.autofocus = false,
  });

  /// The row's leading indicator — a status dot or a priority square.
  final Widget leading;

  /// The row's label text.
  final String label;

  /// Called on tap, `Enter`, or `Space`.
  final VoidCallback onTap;

  /// Announced by `Semantics(button: true)`.
  final String semanticsLabel;

  /// Whether this row claims keyboard focus as soon as its menu opens —
  /// set on the first row of each menu's fixed-order list.
  final bool autofocus;

  @override
  State<BulkOverlayRow> createState() => _BulkOverlayRowState();
}

class _BulkOverlayRowState extends State<BulkOverlayRow> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final fillAlpha = t.fillAlpha;

    final Color fill;
    if (_isPressed) {
      fill = c.primary.withValues(alpha: fillAlpha);
    } else if (_isFocused) {
      fill = c.primarySubtle;
    } else if (_isHovered) {
      fill = c.surfaceHover;
    } else {
      fill = const Color(0x00000000);
    }

    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: FocusableActionDetector(
          autofocus: widget.autofocus,
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              decoration: BoxDecoration(color: fill),
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: _isFocused
                      ? Border.all(color: c.primary, width: 2)
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      widget.leading,
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.label,
                          style: AionText.bodySm.copyWith(
                            color: c.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
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

/// Returns the status-dot color for [status]'s [BulkOverlayRow] leading
/// indicator, per design.md §2.2's fixed table.
Color _statusDotColor(AionColors c, TicketStatus status) => switch (status) {
  TicketStatus.backlog => c.textMuted,
  TicketStatus.todo => c.secondary,
  TicketStatus.inProgress => c.primary,
  TicketStatus.inReview => c.warning,
  TicketStatus.done => c.success,
  TicketStatus.cancelled => c.danger,
};

/// Returns the priority-square leading indicator for [priority], per
/// design.md §3.1's fixed table — a filled 10×10 rounded square in the
/// priority's foreground accent, or a hollow (border-only) square for
/// [TicketPriority.none].
Widget _priorityIndicator(AionColors c, TicketPriority priority) {
  if (priority == TicketPriority.none) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x00000000),
        border: Border.all(color: c.borderStrong, width: 2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: const SizedBox(width: 10, height: 10),
    );
  }
  final fg = switch (priority) {
    TicketPriority.critical => c.priority.criticalFg,
    TicketPriority.high => c.priority.highFg,
    TicketPriority.medium => c.priority.mediumFg,
    TicketPriority.low => c.priority.lowFg,
    TicketPriority.none => c.priority.lowFg,
  };
  return DecoratedBox(
    decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(3)),
    child: const SizedBox(width: 10, height: 10),
  );
}

/// The panel chrome shared by [BulkStatusMenu]/[BulkPriorityMenu]: a
/// `CompositedTransformFollower`-positioned, shadowed, rounded panel with
/// a full-screen transparent dismiss barrier and an `Escape` shortcut,
/// wrapping [rows]. Not a public widget — [BulkStatusMenu]/
/// [BulkPriorityMenu] each build their own row list and delegate the
/// shared chrome here, per design.md §2.1/§3 ("same panel chrome, same
/// row component, same shadow, same open/dismiss/focus behavior").
class _BulkOverlayPanel extends StatelessWidget {
  const _BulkOverlayPanel({
    required this.layerLink,
    required this.openUpward,
    required this.onDismiss,
    required this.rows,
  });

  final LayerLink layerLink;
  final bool openUpward;
  final VoidCallback onDismiss;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        CompositedTransformFollower(
          link: layerLink,
          showWhenUnlinked: false,
          offset: openUpward ? const Offset(0, -8) : const Offset(0, 8),
          targetAnchor: openUpward
              ? Alignment.topCenter
              : Alignment.bottomCenter,
          followerAnchor: openUpward
              ? Alignment.bottomCenter
              : Alignment.topCenter,
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.escape): _DismissIntent(),
            },
            child: Actions(
              actions: {
                _DismissIntent: CallbackAction<_DismissIntent>(
                  onInvoke: (_) {
                    onDismiss();
                    return null;
                  },
                ),
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.borderStrong, width: 1),
                  borderRadius: BorderRadius.all(AionRadius.lg),
                  boxShadow: AionShadows.card(c, t.isDark),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.all(AionRadius.lg),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 200,
                      maxWidth: 240,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Overlay listing every [TicketStatus] value in fixed display order
/// (Backlog · To Do · In Progress · In Review · Done · Cancelled) for
/// [TicketSelectionBar]'s Status trigger. No current-value exclusion — a
/// bulk selection may span tickets with different current statuses.
/// Opens upward by default (the caller flips [openUpward] to `false` when
/// upward would clip the viewport); a full-screen transparent barrier and
/// `Escape` both dismiss without applying. The first row (Backlog)
/// autofocuses on open. Selecting a row calls [onSelected]; the caller
/// ([_BulkStatusPriorityGroupState]) removes this `OverlayEntry`
/// afterward.
class BulkStatusMenu extends StatelessWidget {
  /// Creates a [BulkStatusMenu] anchored to [layerLink].
  const BulkStatusMenu({
    super.key,
    required this.layerLink,
    required this.onSelected,
    required this.onDismiss,
    this.openUpward = true,
  });

  /// Links this overlay's position to its trigger's
  /// `CompositedTransformTarget`.
  final LayerLink layerLink;

  /// Called with the chosen status when a row is selected.
  final ValueChanged<TicketStatus> onSelected;

  /// Called when the overlay is dismissed without a selection (outside
  /// tap or `Escape`).
  final VoidCallback onDismiss;

  /// Whether the panel opens above the trigger (default) or below it.
  final bool openUpward;

  /// Fixed row order — Backlog · To Do · In Progress · In Review · Done ·
  /// Cancelled, per design.md §2.2.
  static const List<TicketStatus> order = [
    TicketStatus.backlog,
    TicketStatus.todo,
    TicketStatus.inProgress,
    TicketStatus.inReview,
    TicketStatus.done,
    TicketStatus.cancelled,
  ];

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return _BulkOverlayPanel(
      layerLink: layerLink,
      openUpward: openUpward,
      onDismiss: onDismiss,
      rows: [
        for (final entry in order.asMap().entries)
          BulkOverlayRow(
            leading: DecoratedBox(
              decoration: BoxDecoration(
                color: _statusDotColor(c, entry.value),
                shape: BoxShape.circle,
              ),
              child: const SizedBox(width: 8, height: 8),
            ),
            label: ticketStatusLabel(context, entry.value),
            semanticsLabel: ticketStatusLabel(context, entry.value),
            autofocus: entry.key == 0,
            onTap: () => onSelected(entry.value),
          ),
      ],
    );
  }
}

/// Overlay listing every [TicketPriority] value in fixed display order
/// (Critical · High · Medium · Low · None) for [TicketSelectionBar]'s
/// Priority trigger. A matched pair with [BulkStatusMenu]: same panel
/// chrome, row component, shadow, and open/dismiss/focus behavior (see
/// [_BulkOverlayPanel]) — only the row set and leading indicator differ.
/// [TicketPriority.none] is a first-class row (hollow-square indicator),
/// bulk-clearing priority on the whole selection when chosen.
class BulkPriorityMenu extends StatelessWidget {
  /// Creates a [BulkPriorityMenu] anchored to [layerLink].
  const BulkPriorityMenu({
    super.key,
    required this.layerLink,
    required this.onSelected,
    required this.onDismiss,
    this.openUpward = true,
  });

  /// Links this overlay's position to its trigger's
  /// `CompositedTransformTarget`.
  final LayerLink layerLink;

  /// Called with the chosen priority when a row is selected.
  final ValueChanged<TicketPriority> onSelected;

  /// Called when the overlay is dismissed without a selection (outside
  /// tap or `Escape`).
  final VoidCallback onDismiss;

  /// Whether the panel opens above the trigger (default) or below it.
  final bool openUpward;

  /// Fixed row order — Critical · High · Medium · Low · None, per
  /// design.md §3.1.
  static const List<TicketPriority> order = [
    TicketPriority.critical,
    TicketPriority.high,
    TicketPriority.medium,
    TicketPriority.low,
    TicketPriority.none,
  ];

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return _BulkOverlayPanel(
      layerLink: layerLink,
      openUpward: openUpward,
      onDismiss: onDismiss,
      rows: [
        for (final entry in order.asMap().entries)
          BulkOverlayRow(
            leading: _priorityIndicator(c, entry.value),
            label: ticketPriorityLabel(context, entry.value),
            semanticsLabel: ticketPriorityLabel(context, entry.value),
            autofocus: entry.key == 0,
            onTap: () => onSelected(entry.value),
          ),
      ],
    );
  }
}
