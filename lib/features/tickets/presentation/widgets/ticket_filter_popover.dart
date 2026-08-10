// presentation/widgets/ticket_filter_popover.dart — TicketFilterPopover overlay widget (presentation layer).

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_board_view.dart'
    show ticketPriorityLabel, ticketStatusLabel;

/// The `TicketsListScreen` filters trigger's open overlay panel: three
/// independently-toggleable checkbox groups (Status, Type, Priority).
/// Structurally mirrors [SelectionMenu]'s `LayerLink`/
/// `CompositedTransformFollower`/`OverlayEntry` mechanics, generalized
/// from one flat single-select list to three multi-select groups. Unlike
/// [SelectionMenu]/`AppDropdown`, selecting a row never closes the
/// panel — multi-select needs to stay open across several taps — only
/// tapping outside or pressing `Escape` dismisses it.
class TicketFilterPopover extends StatefulWidget {
  /// Creates a [TicketFilterPopover] wrapping [trigger].
  const TicketFilterPopover({
    super.key,
    required this.trigger,
    required this.selectedStatuses,
    required this.selectedTypes,
    required this.selectedPriorities,
    required this.onToggleStatus,
    required this.onToggleType,
    required this.onTogglePriority,
    this.onOpenChanged,
  });

  /// The always-visible tappable widget (the "Filters" trigger button).
  final Widget trigger;

  /// Called with `true` when the overlay opens and `false` when it
  /// closes — lets a stateful [trigger] render its own "open" look
  /// (e.g. holding a focus-ring appearance while its own popover is up).
  /// Mirrors [SelectionMenu.onOpenChanged]. Optional; a [trigger] that
  /// doesn't need this may omit it.
  final ValueChanged<bool>? onOpenChanged;

  /// Currently selected [TicketStatus] values, used to render each
  /// status row's checked state.
  final Set<TicketStatus> selectedStatuses;

  /// Currently selected [TicketType] values, used to render each type
  /// row's checked state.
  final Set<TicketType> selectedTypes;

  /// Currently selected [TicketPriority] values, used to render each
  /// priority row's checked state.
  final Set<TicketPriority> selectedPriorities;

  /// Called with the tapped/activated status row's value.
  final ValueChanged<TicketStatus> onToggleStatus;

  /// Called with the tapped/activated type row's value.
  final ValueChanged<TicketType> onToggleType;

  /// Called with the tapped/activated priority row's value.
  final ValueChanged<TicketPriority> onTogglePriority;

  /// The `Type` group's fixed, client-side-filtered item list —
  /// `page`/`resource` moved to the Documentation section and no longer
  /// appear here; `signal`/`release` excluded as a pre-existing gap.
  /// Mirrors the same hardcoded list `TicketsListScreen`'s old
  /// `AppDropdown<TicketType?>` used.
  static const typeOptions = [
    TicketType.epic,
    TicketType.story,
    TicketType.task,
    TicketType.bug,
    TicketType.chat,
  ];

  @override
  State<TicketFilterPopover> createState() => _TicketFilterPopoverState();
}

class _TicketFilterPopoverState extends State<TicketFilterPopover> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  @override
  void didUpdateWidget(covariant TicketFilterPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Every toggle re-runs `searchTickets`, which rebuilds this widget
    // with fresh `selectedX` sets from the cubit — but the already-open
    // `OverlayEntry`'s content isn't part of this widget's own subtree
    // (it's inserted into the ancestor `Overlay`), so it never repaints
    // on its own just because this widget rebuilt. Without this, a
    // checked/unchecked row inside an already-open popover would keep
    // showing its state from when the popover was opened, even though
    // the trigger badge, chip row, and ticket list (driven directly by
    // `TicketsListScreen`'s own `BlocBuilder`) all update correctly.
    _overlayEntry?.markNeedsBuild();
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
    // Guards against setState-after-dispose, same as SelectionMenu/
    // AppDropdown's own overlay-dismiss precedent.
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
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _GroupHeader(
                                  context.l10n.ticketsListFilterStatusLabel,
                                ),
                                for (final status in TicketStatus.values)
                                  OverlayMenuItem(
                                    onTap: () =>
                                        widget.onToggleStatus(status),
                                    semanticsLabel: ticketStatusLabel(
                                      context,
                                      status,
                                    ),
                                    autofocus: status == TicketStatus.values.first,
                                    child: _CheckRow(
                                      checked: widget.selectedStatuses
                                          .contains(status),
                                      label: ticketStatusLabel(
                                        context,
                                        status,
                                      ),
                                    ),
                                  ),
                                const _GroupDivider(),
                                _GroupHeader(
                                  context.l10n.ticketsListFilterTypeLabel,
                                ),
                                for (final type
                                    in TicketFilterPopover.typeOptions)
                                  OverlayMenuItem(
                                    onTap: () => widget.onToggleType(type),
                                    semanticsLabel: ticketTypeLabel(
                                      context,
                                      type,
                                    ),
                                    child: _CheckRow(
                                      checked: widget.selectedTypes.contains(
                                        type,
                                      ),
                                      label: ticketTypeLabel(context, type),
                                    ),
                                  ),
                                const _GroupDivider(),
                                _GroupHeader(
                                  context.l10n.ticketsListFilterPriorityLabel,
                                ),
                                for (final priority in TicketPriority.values)
                                  OverlayMenuItem(
                                    onTap: () =>
                                        widget.onTogglePriority(priority),
                                    semanticsLabel: ticketPriorityLabel(
                                      context,
                                      priority,
                                    ),
                                    child: _CheckRow(
                                      checked: widget.selectedPriorities
                                          .contains(priority),
                                      label: ticketPriorityLabel(
                                        context,
                                        priority,
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
        child: GestureDetector(onTap: _toggleOverlay, child: widget.trigger),
      ),
    );
  }
}

/// One group's caption header (e.g. "Status") — non-interactive, no
/// focus stop.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 8, 13, 6),
      child: Text(
        label.toUpperCase(),
        style: AionText.caption.copyWith(color: c.textMuted),
      ),
    );
  }
}

/// One checkbox row's content: an [AppCheckbox] (presentational — the
/// enclosing [OverlayMenuItem] owns the tap target) plus [label].
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.checked, required this.label});

  final bool checked;
  final String label;

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

/// A hairline divider between two filter groups, with vertical breathing
/// room on both sides. Non-interactive, no focus stop.
class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.border, width: 1)),
        ),
        child: const SizedBox(height: 1),
      ),
    );
  }
}
