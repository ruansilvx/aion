// presentation/widgets/ticket_filter_popover.dart — TicketFilterPopover overlay widget (presentation layer).

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/workflow_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/presentation/cubit/workflow_config_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/workflow_config_state.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_board_view.dart'
    show ticketPriorityLabel, ticketStatusLabel;
import 'package:aion/features/tickets/presentation/widgets/status_dot.dart';

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
    this.onFocusChanged,
  });

  /// The always-visible tappable widget (the "Filters" trigger button).
  final Widget trigger;

  /// Called with `true` when the overlay opens and `false` when it
  /// closes — lets a stateful [trigger] render its own "open" look
  /// (e.g. holding a focus-ring appearance while its own popover is up).
  /// Mirrors [SelectionMenu.onOpenChanged]. Optional; a [trigger] that
  /// doesn't need this may omit it.
  final ValueChanged<bool>? onOpenChanged;

  /// Called with `true` when [trigger] gains keyboard focus and `false`
  /// when it loses it — lets a stateful [trigger] render its own
  /// `Focused` look (design.md §3.2) independent of whether the popover
  /// is actually open, since a keyboard user tabbing onto the trigger
  /// hasn't necessarily activated it yet. Fed by the wrapping
  /// [FocusableActionDetector]'s own `onShowFocusHighlight`. Optional; a
  /// [trigger] that doesn't need this may omit it.
  final ValueChanged<bool>? onFocusChanged;

  /// Currently selected status names, used to render each status row's
  /// checked state.
  final Set<String> selectedStatuses;

  /// Currently selected [TicketType] values, used to render each type
  /// row's checked state.
  final Set<TicketType> selectedTypes;

  /// Currently selected [TicketPriority] values, used to render each
  /// priority row's checked state.
  final Set<TicketPriority> selectedPriorities;

  /// Called with the tapped/activated status row's value.
  final ValueChanged<String> onToggleStatus;

  /// Called with the tapped/activated type row's value.
  final ValueChanged<TicketType> onToggleType;

  /// Called with the tapped/activated priority row's value.
  final ValueChanged<TicketPriority> onTogglePriority;

  /// The `Type` group's fixed, client-side-filtered item list —
  /// `page`/`resource` moved to the Documentation section and no longer appear
  /// here; `idea`/`knownGap`/`openQuestion`/`release` excluded (the first
  /// three inherit `signal`'s original pre-existing-gap exclusion — see
  /// `AIO-934`). Mirrors the same hardcoded list `TicketsListScreen`'s old
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
    // Every toggle re-runs `searchTickets`, which rebuilds this widget with
    // fresh `selectedX` sets from the cubit — but the already-open
    // `OverlayEntry`'s content isn't part of this widget's own subtree (it's
    // inserted into the ancestor `Overlay`), so it never repaints on its own
    // just because this widget rebuilt. Without this, a checked/unchecked row
    // inside an already-open popover would keep showing its state from when
    // the popover was opened, even though the trigger badge, chip row, and
    // ticket list (driven directly by `TicketsListScreen`'s own `BlocBuilder`)
    // all update correctly. Deferred to a post-frame callback rather than
    // called synchronously here — this `didUpdateWidget` can itself run nested
    // inside another ancestor's build pass (concretely: the very first open,
    // where `_showOverlay`'s `onOpenChanged` callback marks
    // `_TicketFilterAndSortSection` dirty in the same frame this widget's own
    // state changes), and the `OverlayEntry` lives outside this widget's own
    // subtree (under the root `Overlay`), so a synchronous `markNeedsBuild()`
    // here hits Flutter's "setState called during build" assertion for a
    // non-descendant target — reproducible by tapping this trigger on a native
    // desktop build (see `AIO-1069`'s manual verification pass).
    // `TicketSortPopover`'s own `didUpdateWidget` already used this fix; this
    // one hadn't been updated to match until now.
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
        // `context.watch` — this builder re-runs on every
        // `OverlayEntry.markNeedsBuild()`/ancestor rebuild, so the open
        // panel picks up a live status-set change rather than only
        // reflecting whatever was current when it opened.
        final workflowState = context.watch<WorkflowConfigCubit>().state;
        final statusOrder = resolveSharedStatusOrder(workflowState);
        final statusScope = workflowState is WorkflowConfigLoaded
            ? workflowState.sharedBaseStatuses
            : const <WorkflowStatus>[];
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
                                for (final status in statusOrder)
                                  OverlayMenuItem(
                                    onTap: () =>
                                        widget.onToggleStatus(status),
                                    semanticsLabel: ticketStatusLabel(
                                      context,
                                      status,
                                    ),
                                    autofocus: status == statusOrder.first,
                                    child: _CheckRow(
                                      checked: widget.selectedStatuses
                                          .contains(status),
                                      label: ticketStatusLabel(
                                        context,
                                        status,
                                      ),
                                      accent: StatusDot(
                                        color: statusDotColorForName(
                                          c,
                                          statusScope,
                                          status,
                                        ),
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
                                      accent: _TypeAccentSquare(type: type),
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
                                      accent: _PriorityAccentDot(
                                        priority: priority,
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
        onShowFocusHighlight: widget.onFocusChanged,
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
/// enclosing [OverlayMenuItem] owns the tap target) plus [label] and an
/// [accent] swatch echoing the value's color elsewhere in the app
/// (design.md §4.5's "Optional leading accent" — a `StatusDot`
/// (`status_dot.dart`) for the Status group, [_TypeAccentSquare]/
/// [_PriorityAccentDot] for Type/Priority).
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.checked, required this.label, this.accent});

  final bool checked;
  final String label;

  /// The field-specific accent swatch shown between the checkbox and the
  /// label, or `null` for no accent.
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

/// A 10×10, `radius: 2` accent square for a `_CheckRow`'s Type group,
/// mirroring `TypeChip`'s own color mapping (`tickets_list_screen.dart`).
class _TypeAccentSquare extends StatelessWidget {
  const _TypeAccentSquare({required this.type});

  final TicketType type;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final color = switch (type) {
      TicketType.story => c.typeStory,
      TicketType.epic => c.typeEpic,
      TicketType.resource => c.typeResource,
      TicketType.page => c.typePage,
      TicketType.idea => c.typeIdea,
      TicketType.knownGap => c.typeKnownGap,
      TicketType.openQuestion => c.typeOpenQuestion,
      TicketType.release => c.typeRelease,
      TicketType.chat => c.typeChat,
      TicketType.bug => c.typeBug,
      _ => c.typeTask,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
      child: const SizedBox(width: 10, height: 10),
    );
  }
}

/// An 8×8 accent dot for a `_CheckRow`'s Priority group, in the level's
/// `fg` tone — mirroring `PriorityBadge`'s own color mapping
/// (`tickets_list_screen.dart`).
class _PriorityAccentDot extends StatelessWidget {
  const _PriorityAccentDot({required this.priority});

  final TicketPriority priority;

  @override
  Widget build(BuildContext context) {
    final AionPriorityColors p = ThemeScope.of(context).colors.priority;
    final color = switch (priority) {
      TicketPriority.critical => p.criticalFg,
      TicketPriority.high => p.highFg,
      TicketPriority.medium => p.mediumFg,
      TicketPriority.low => p.lowFg,
      TicketPriority.none => p.lowFg,
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const SizedBox(width: 8, height: 8),
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
