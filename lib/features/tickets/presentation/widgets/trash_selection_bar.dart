// presentation/widgets/trash_selection_bar.dart — Floating bulk Restore/Delete-forever contextual bar for TrashScreen's selection mode (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';

/// Width at and above which [TrashSelectionBar] collapses its two-row
/// phone layout into a single row (Cancel · count · Select-all · Restore
/// · Delete forever), with the two action buttons becoming intrinsic-
/// width instead of `Expanded` — matches design.md's `TrashSelectionBar`
/// export §3.6 "Wide-viewport variant". Also doubles as that single row's
/// own max-width cap. Widened from the export's literal 620 — at 620 (and
/// even 680) the six elements (Cancel, count, Select-all, both full-
/// label action buttons) don't reliably fit on one line without
/// ellipsizing the count label, depending on its exact text ("Deselect
/// all" vs. "Select all") and locale.
const double _kWideBreakpoint = 760;

/// Minimum content-box height of the Restore/Delete-forever action
/// buttons — the `kBarActionMinHeight` constant from design.md §0.4 (its
/// own padding brings the actual hit target to ≥ 44).
const double _kBarActionMinHeight = 40;

/// The floating, contextual bar shown while [TicketSelectionCubit]'s
/// selection mode is active on `TrashScreen`: a leading Cancel control,
/// the selected count, a Select-all/Deselect-all toggle, and exactly two
/// bulk actions — Restore (non-destructive, no confirmation) and Delete
/// forever (destructive, gated behind `TrashScreen`'s own confirm
/// dialog). Visually modeled on `TicketSelectionBar`'s outer chrome
/// (duplicated, not shared — that file's chrome widgets are private to
/// their own file) but with no overlay/menu machinery, since neither
/// action opens a sub-picker. No compact/breakpoint icon-only mode
/// (unlike `TicketSelectionBar`) — see proposal.md's Non-goals.
class TrashSelectionBar extends StatelessWidget {
  /// Creates a [TrashSelectionBar].
  const TrashSelectionBar({
    super.key,
    required this.selectedCount,
    required this.allSelected,
    required this.onCancel,
    required this.onSelectAll,
    required this.onRestore,
    required this.onDeleteForever,
  });

  /// How many trashed root tickets are currently selected.
  final int selectedCount;

  /// Whether every currently loaded trashed root ticket is selected —
  /// drives the Select-all toggle's label ("Select all" vs.
  /// "Deselect all").
  final bool allSelected;

  /// Called when the Cancel control is tapped.
  final VoidCallback onCancel;

  /// Called when the Select-all/Deselect-all toggle is tapped.
  final VoidCallback onSelectAll;

  /// Called when Restore is tapped. Only reachable when [selectedCount]
  /// is greater than zero — the button renders disabled otherwise. No
  /// confirmation — the caller performs the restore immediately.
  final VoidCallback onRestore;

  /// Called when Delete forever is tapped. Only reachable when
  /// [selectedCount] is greater than zero — the button renders disabled
  /// otherwise. The caller is expected to gate the actual deletion behind
  /// its own confirm dialog before acting.
  final VoidCallback onDeleteForever;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final topRow = _TopRow(
      selectedCount: selectedCount,
      allSelected: allSelected,
      onCancel: onCancel,
      onSelectAll: onSelectAll,
    );
    final restoreButton = _TrashBarActionButton(
      icon: PhosphorIcons.arrowUUpLeftLight,
      label: context.l10n.ticketTrashRestoreAction,
      destructive: false,
      onTap: selectedCount > 0 ? onRestore : null,
    );
    final deleteButton = _TrashBarActionButton(
      icon: PhosphorIcons.trashLight,
      label: context.l10n.ticketTrashPermanentDeleteAction,
      destructive: true,
      onTap: selectedCount > 0 ? onDeleteForever : null,
    );

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
            if (constraints.maxWidth >= _kWideBreakpoint) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _kWideBreakpoint),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: topRow),
                      const SizedBox(width: 10),
                      restoreButton,
                      const SizedBox(width: 10),
                      deleteButton,
                    ],
                  ),
                ),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                topRow,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: restoreButton),
                    const SizedBox(width: 8),
                    Expanded(child: deleteButton),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// [TrashSelectionBar]'s first row: the Cancel control, the selected-
/// count label, a flexible spacer, and the Select-all/Deselect-all
/// toggle. The count label sits in an [Expanded] (not a bare [Spacer]
/// alongside it) so it shrinks and ellipsizes on very narrow desktop
/// windows instead of pushing the Select-all toggle past the bar's own
/// width.
class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.selectedCount,
    required this.allSelected,
    required this.onCancel,
    required this.onSelectAll,
  });

  final int selectedCount;
  final bool allSelected;
  final VoidCallback onCancel;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _CancelControl(onTap: onCancel),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            context.l10n.ticketSelectionCountLabel(selectedCount),
            style: AionText.button.copyWith(
              color: selectedCount > 0 ? c.textPrimary : c.textMuted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        _SelectAllToggle(allSelected: allSelected, onTap: onSelectAll),
      ],
    );
  }
}

/// [TrashSelectionBar]'s leading Cancel control — a `34×34` icon button,
/// duplicating [TicketSelectionBar]'s private `_CancelControl` (same
/// shape, glyph, and hover/focus behavior; not shared, since that
/// widget is private to its own file).
class _CancelControl extends StatefulWidget {
  const _CancelControl({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_CancelControl> createState() => _CancelControlState();
}

class _CancelControlState extends State<_CancelControl> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final boxShadow = _isFocused
        ? AionShadows.focus(c, t.isDark)
        : const <BoxShadow>[];

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
          onShowFocusHighlight: (value) => setState(() => _isFocused = value),
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
                      PhosphorIcons.xLight,
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

/// [TrashSelectionBar]'s Select-all/Deselect-all ghost text button — a
/// plain tap target, no hover/focus state machine, matching design.md's
/// minimal "text only" spec for this control.
class _SelectAllToggle extends StatelessWidget {
  const _SelectAllToggle({required this.allSelected, required this.onTap});

  final bool allSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final label = allSelected
        ? context.l10n.ticketSelectionDeselectAllAction
        : context.l10n.ticketSelectionSelectAllAction;

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Text(
            label,
            style: AionText.button.copyWith(fontSize: 12.5, color: c.primary),
          ),
        ),
      ),
    );
  }
}

/// One of [TrashSelectionBar]'s two bulk-action buttons (Restore /
/// Delete forever). [destructive] selects between the neutral
/// (`surfaceHover`-filled) Restore tone and the danger (`danger`-filled,
/// white-content) Delete-forever tone; both share the same dimensions,
/// padding, radius, and default/hover/focused/pressed/disabled state
/// machine shape (`GestureDetector` → `Focus` → `AnimatedContainer`).
/// [onTap] is `null` to render the disabled state (0 selected).
class _TrashBarActionButton extends StatefulWidget {
  const _TrashBarActionButton({
    required this.icon,
    required this.label,
    required this.destructive,
    required this.onTap,
  });

  /// The button's leading glyph.
  final PhosphorIconData icon;

  /// The button's text label.
  final String label;

  /// `true` for Delete forever's danger tone; `false` for Restore's
  /// neutral tone.
  final bool destructive;

  /// Called on tap or keyboard activation. `null` renders the disabled
  /// state and ignores input.
  final VoidCallback? onTap;

  @override
  State<_TrashBarActionButton> createState() => _TrashBarActionButtonState();
}

class _TrashBarActionButtonState extends State<_TrashBarActionButton> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final enabled = widget.onTap != null;
    final fillAlpha = t.isDark ? fillAlphaObsidian : fillAlphaArctic;

    // Delete forever's hover/pressed fill — a one-off computed blend (no
    // stored `dangerHover` token), matching how `AionColorsHubTokens`'s
    // own derived shades are computed inline rather than stored.
    final dangerHover = Color.alphaBlend(
      const Color(0xFF000000).withValues(alpha: 0.08),
      c.danger,
    );

    final Color fill;
    final Color? border;
    final Color content;
    var opacity = 1.0;

    if (!enabled) {
      fill = c.surfaceHover;
      border = widget.destructive ? null : c.border;
      content = c.textMuted;
      opacity = 0.6;
    } else if (_isPressed) {
      fill = widget.destructive
          ? dangerHover
          : c.primary.withValues(alpha: fillAlpha);
      border = widget.destructive ? null : c.borderStrong;
      content = widget.destructive ? const Color(0xFFFFFFFF) : c.textPrimary;
    } else if (_isHovered) {
      fill = widget.destructive ? dangerHover : c.surfaceHover;
      border = widget.destructive ? null : c.borderStrong;
      content = widget.destructive ? const Color(0xFFFFFFFF) : c.textPrimary;
    } else {
      fill = widget.destructive ? c.danger : c.surfaceHover;
      border = widget.destructive ? null : c.borderStrong;
      content = widget.destructive ? const Color(0xFFFFFFFF) : c.textPrimary;
    }

    final ring = _isFocused && enabled
        ? AionShadows.focus(
            c,
            t.isDark,
            color: widget.destructive ? c.danger : null,
          )
        : const <BoxShadow>[];

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: enabled ? (_) => setState(() => _isHovered = true) : null,
        onExit: enabled ? (_) => setState(() => _isHovered = false) : null,
        child: FocusableActionDetector(
          enabled: enabled,
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap?.call();
                return null;
              },
            ),
          },
          onShowFocusHighlight: (value) => setState(() => _isFocused = value),
          child: GestureDetector(
            onTap: widget.onTap,
            onTapDown: enabled
                ? (_) => setState(() => _isPressed = true)
                : null,
            onTapUp: enabled ? (_) => setState(() => _isPressed = false) : null,
            onTapCancel: enabled
                ? () => setState(() => _isPressed = false)
                : null,
            child: AnimatedScale(
              scale: _isPressed && enabled ? 0.98 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Opacity(
                opacity: opacity,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  constraints: const BoxConstraints(
                    minHeight: _kBarActionMinHeight,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: fill,
                    border: border != null
                        ? Border.all(color: border, width: 1)
                        : null,
                    borderRadius: BorderRadius.all(AionRadius.md),
                    boxShadow: ring,
                  ),
                  // Bounded via ConstrainedBox, not left to the ambient
                  // constraints: in the wide-viewport variant (§3.6) this
                  // button is a plain (non-Expanded) Row child, which hands
                  // its subtree an *unbounded* max width to measure its own
                  // intrinsic size — and a Flexible inside an unbounded Row
                  // throws. Capping at 220 is a no-op there (well past any
                  // label's natural width) but gives the Flexible below a
                  // legal, finite bound in both this widget's call sites.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        PhosphorIcon(widget.icon, size: 15, color: content),
                        const SizedBox(width: 7),
                        // Flexible, not a bare Text — at very narrow phone
                        // widths (two Expanded buttons sharing the bar) a
                        // label like "Delete permanently" can outgrow its
                        // half of the bar; ellipsizing beats a hard
                        // overflow (see proposal.md's Non-goals: no
                        // dedicated compact/icon-only mode for this bar, so
                        // labels fit-or-ellipsize instead of swapping to
                        // icon-only).
                        Flexible(
                          child: Text(
                            widget.label,
                            style: AionText.button.copyWith(
                              fontSize: 13.5,
                              color: content,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}
