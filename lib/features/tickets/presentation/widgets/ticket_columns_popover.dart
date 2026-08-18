// presentation/widgets/ticket_columns_popover.dart — TicketColumnsPopover overlay widget (presentation layer).

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_board_view.dart'
    show ticketStatusLabel;

/// The Board header's "Columns" trigger's open overlay panel: a single
/// checkbox group listing all 6 [TicketStatus] values, one row per
/// status, **checked meaning the column is currently visible** — the
/// inverse of `TicketFilterPopover`'s "checked means selected/included in
/// the filter." Structurally a straight copy of `TicketFilterPopover`'s
/// `Overlay`/`OverlayEntry`/`CompositedTransformFollower`/`LayerLink`/
/// `Escape`-to-dismiss mechanics, reduced to one flat group (no
/// `_GroupHeader`, no `_GroupDivider` — a single group needs neither).
/// Like `TicketFilterPopover`, toggling a row never closes the panel —
/// only tapping outside or pressing `Escape` dismisses it. See
/// `aion-arch/changes/list-board-view-and-column-visibility/design.md`
/// §7.1 and that change's Component Spec §3.
class TicketColumnsPopover extends StatefulWidget {
  /// Creates a [TicketColumnsPopover] wrapping [trigger].
  const TicketColumnsPopover({
    super.key,
    required this.trigger,
    required this.hiddenStatuses,
    required this.onToggleColumn,
    this.onOpenChanged,
    this.onFocusChanged,
  });

  /// The always-visible tappable widget (the "Columns" trigger button).
  final Widget trigger;

  /// The [TicketStatus] values whose board column is currently hidden —
  /// every other status renders its row checked (visible).
  final Set<TicketStatus> hiddenStatuses;

  /// Called with the tapped/activated row's status.
  final ValueChanged<TicketStatus> onToggleColumn;

  /// Called with `true` when the overlay opens and `false` when it
  /// closes — lets a stateful [trigger] render its own "open" look.
  /// Mirrors `TicketFilterPopover.onOpenChanged`. Optional; a [trigger]
  /// that doesn't need this may omit it.
  final ValueChanged<bool>? onOpenChanged;

  /// Called with `true` when [trigger] gains keyboard focus and `false`
  /// when it loses it — lets a stateful [trigger] render its own
  /// `Focused` look independent of whether the popover is actually open.
  /// Optional; a [trigger] that doesn't need this may omit it.
  final ValueChanged<bool>? onFocusChanged;

  @override
  State<TicketColumnsPopover> createState() => _TicketColumnsPopoverState();
}

class _TicketColumnsPopoverState extends State<TicketColumnsPopover> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  @override
  void didUpdateWidget(covariant TicketColumnsPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Toggling a row re-reads TicketsCubit.hiddenBoardColumns and forces
    // a rebuild at the screen level (see TicketsListScreen's
    // _handleColumnVisibilityToggled — hiding a column never emits a
    // TicketsState, so nothing else would rebuild this widget), which
    // rebuilds this widget with a fresh hiddenStatuses set — but the
    // already-open OverlayEntry's content isn't part of this widget's
    // own subtree (it's inserted into the ancestor Overlay), so it never
    // repaints on its own just because this widget rebuilt. Deferred to
    // a post-frame callback rather than called synchronously here —
    // same fix TicketSortPopover's own didUpdateWidget already applies
    // (and TicketFilterPopover's didn't, until this change): this
    // didUpdateWidget can run nested inside an ancestor's own build pass
    // (e.g. the very first open, where _showOverlay's onOpenChanged
    // callback marks _TicketFilterAndSortSection dirty in the same
    // frame this widget's own state changes), and the OverlayEntry lives
    // outside this widget's subtree (under the root Overlay), so a
    // synchronous markNeedsBuild() here can hit Flutter's "setState
    // called during build" assertion for a non-descendant target.
    final entry = _overlayEntry;
    if (entry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_overlayEntry == entry) entry.markNeedsBuild();
      });
    }
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  void _toggleOverlay() {
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    // Guards against setState-after-dispose, same as
    // TicketFilterPopover/SelectionMenu/AppDropdown's own
    // overlay-dismiss precedent.
    if (mounted) {
      setState(() => _isOpen = false);
    } else {
      _isOpen = false;
    }
    widget.onOpenChanged?.call(false);
  }

  void _showOverlay() {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final overlay = Overlay.of(context);

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverlay,
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 6),
              targetAnchor: Alignment.bottomLeft,
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                },
                child: Actions(
                  actions: {
                    DismissIntent: CallbackAction<DismissIntent>(
                      onInvoke: (_) {
                        _removeOverlay();
                        return null;
                      },
                    ),
                  },
                  child: Focus(
                    autofocus: true,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.all(AionRadius.lg),
                        border: Border.all(color: c.borderStrong, width: 1),
                        boxShadow: AionShadows.card(c, t.isDark),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 236),
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final status in TicketStatus.values)
                                  OverlayMenuItem(
                                    onTap: () =>
                                        widget.onToggleColumn(status),
                                    semanticsLabel: ticketStatusLabel(
                                      context,
                                      status,
                                    ),
                                    autofocus: status == TicketStatus.values.first,
                                    child: _ColumnRow(
                                      checked: !widget.hiddenStatuses
                                          .contains(status),
                                      label: ticketStatusLabel(
                                        context,
                                        status,
                                      ),
                                      accent: _StatusAccentDot(status: status),
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
            ),
          ],
        );
      },
    );

    overlay.insert(_overlayEntry!);
    setState(() => _isOpen = true);
    widget.onOpenChanged?.call(true);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: FocusableActionDetector(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggleOverlay();
              return null;
            },
          ),
        },
        onShowFocusHighlight: widget.onFocusChanged,
        child: GestureDetector(onTap: _toggleOverlay, child: widget.trigger),
      ),
    );
  }
}

/// One `_ColumnRow`'s content: an [AppCheckbox] (presentational — the
/// enclosing [OverlayMenuItem] owns the tap target) plus [label] and an
/// [accent] status dot. Checked means "this column is currently
/// visible" — see [TicketColumnsPopover]'s own dartdoc.
class _ColumnRow extends StatelessWidget {
  const _ColumnRow({required this.checked, required this.label, this.accent});

  final bool checked;
  final String label;

  /// The status's accent dot, or `null` for none.
  final Widget? accent;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IgnorePointer(
            child: AppCheckbox(value: checked, onChanged: (_) {}),
          ),
          const SizedBox(width: 10),
          if (accent != null) ...[accent!, const SizedBox(width: 8)],
          Expanded(
            child: Text(
              label,
              style: AionText.bodySm.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// An 8×8 accent dot for a [_ColumnRow], mirroring `StatusIndicator`'s own
/// color mapping (`tickets_board_view.dart`): [TicketStatus.backlog] →
/// `c.textMuted`, [TicketStatus.inProgress] → `c.primary`,
/// [TicketStatus.done] → `c.success`, every other status → `c.textMuted`.
/// A private duplicate of `TicketFilterPopover`'s own `_StatusAccentDot`
/// (that one is private to its own file and can't be imported/shared).
class _StatusAccentDot extends StatelessWidget {
  const _StatusAccentDot({required this.status});

  final TicketStatus status;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final color = switch (status) {
      TicketStatus.backlog => c.textMuted,
      TicketStatus.inProgress => c.primary,
      TicketStatus.done => c.success,
      _ => c.textMuted,
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const SizedBox(width: 8, height: 8),
    );
  }
}
