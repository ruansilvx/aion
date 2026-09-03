// presentation/widgets/ticket_sort_popover.dart — TicketSortPopover overlay widget (presentation layer).

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_direction.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_field.dart';

/// The `TicketsListScreen` Sort trigger's open overlay panel: a flat list
/// of one row per [TicketSortField], single-active-key selection with a
/// twist — unlike `SelectionMenu` (which excludes the current value),
/// **every** row (including the currently active field) is always
/// rendered, since tapping the already-active row is a valid, meaningful
/// action here (flips its direction) rather than a wasted tap.
/// Structurally mirrors `TicketFilterPopover`'s `LayerLink`/
/// `CompositedTransformFollower`/`OverlayEntry` mechanics and
/// `Escape`-to-dismiss `Shortcuts`/`Actions` wiring. See
/// `AIO-2371`.
class TicketSortPopover extends StatefulWidget {
  /// Creates a [TicketSortPopover] wrapping [trigger].
  const TicketSortPopover({
    super.key,
    required this.trigger,
    required this.currentSort,
    required this.hasActiveQuery,
    required this.onSortSelected,
    this.onOpenChanged,
    this.onFocusChanged,
  });

  /// The always-visible tappable widget (the "Sort" trigger button).
  final Widget trigger;

  /// The currently active sort — drives which row renders as selected
  /// and which direction glyph it shows.
  final TicketListSort currentSort;

  /// Whether a search query is currently active — gates whether the
  /// [TicketSortField.relevance] row is enabled/selectable. Selecting it
  /// with no query active would immediately fall back to `createdAt`
  /// descending anyway (see `TicketsCubit._implicitSort`/
  /// `TrashCubit._resolveSort`), so it's disabled rather than offering a
  /// choice that silently does something else.
  final bool hasActiveQuery;

  /// Called with the newly resolved [TicketListSort] whenever a row is
  /// tapped or keyboard-activated — see [_TicketSortPopoverState._handleTap].
  final ValueChanged<TicketListSort> onSortSelected;

  /// Called with `true` when the overlay opens and `false` when it
  /// closes — lets a stateful [trigger] render its own "open" look.
  /// Mirrors `TicketFilterPopover.onOpenChanged`. Optional; a [trigger]
  /// that doesn't need this may omit it.
  final ValueChanged<bool>? onOpenChanged;

  /// Called with `true` when [trigger] gains keyboard focus and `false`
  /// when it loses it, independent of whether the popover is actually
  /// open. Mirrors `TicketFilterPopover.onFocusChanged`. Optional; a
  /// [trigger] that doesn't need this may omit it.
  final ValueChanged<bool>? onFocusChanged;

  @override
  State<TicketSortPopover> createState() => _TicketSortPopoverState();
}

class _TicketSortPopoverState extends State<TicketSortPopover> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  @override
  void didUpdateWidget(covariant TicketSortPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Selecting a row re-runs the search, which rebuilds this widget with
    // a fresh `currentSort` — but the already-open `OverlayEntry`'s
    // content isn't part of this widget's own subtree (it's inserted
    // into the ancestor `Overlay`), so it never repaints on its own just
    // because this widget rebuilt (same underlying need
    // `TicketFilterPopover`'s identical-looking `markNeedsBuild()` call
    // addresses). Deferred to a post-frame callback rather than called
    // synchronously here — this `didUpdateWidget` can itself run nested
    // inside another ancestor's build/layout pass (e.g. a `LayoutBuilder`
    // higher up rebuilding this row during layout), and the `OverlayEntry`
    // lives outside this widget's own subtree (under the root `Overlay`),
    // so a synchronous `markNeedsBuild()` here can hit Flutter's "setState
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

  /// The direction a *newly activated* [field] should default to, so the
  /// first tap on a field is useful without a second — used only when
  /// switching into [field], never when flipping an already-active one
  /// (see [_handleTap]).
  TicketSortDirection _defaultDirectionFor(TicketSortField field) =>
      switch (field) {
        // Ignored for relevance — its ordering is always bm25 ascending.
        TicketSortField.relevance => TicketSortDirection.descending,
        TicketSortField.priority => TicketSortDirection.ascending,
        TicketSortField.status => TicketSortDirection.ascending,
        TicketSortField.type => TicketSortDirection.ascending,
        TicketSortField.createdAt => TicketSortDirection.descending,
        TicketSortField.updatedAt => TicketSortDirection.descending,
      };

  /// Resolves a tap on [field]'s row into the [TicketListSort]
  /// [TicketSortPopover.onSortSelected] is called with: flips
  /// [TicketSortPopover.currentSort]'s direction if [field] is already
  /// active — a no-op for [TicketSortField.relevance], which has no
  /// direction to flip — or switches to [field] at its
  /// [_defaultDirectionFor] direction otherwise, mirroring a
  /// click-to-sort table header. Never called for a disabled row (see
  /// [TicketSortPopover.hasActiveQuery]).
  void _handleTap(TicketSortField field) {
    if (field == widget.currentSort.field) {
      if (field == TicketSortField.relevance) return;
      widget.onSortSelected(
        TicketListSort(
          field: field,
          direction:
              widget.currentSort.direction == TicketSortDirection.ascending
              ? TicketSortDirection.descending
              : TicketSortDirection.ascending,
        ),
      );
    } else {
      widget.onSortSelected(
        TicketListSort(field: field, direction: _defaultDirectionFor(field)),
      );
    }
  }

  /// [field]'s row semantics label: its display label alone when
  /// inactive, or the label plus a direction suffix
  /// (`ticketsListSortDirectionAscendingSemantics`/
  /// `...DescendingSemantics`) when active — mirrors how
  /// `ticketStatusLabel`/etc. compose into `TicketFilterPopover`'s own
  /// `semanticsLabel` usage.
  String _rowSemanticsLabel(BuildContext context, TicketSortField field) {
    final label = ticketSortFieldLabel(context, field);
    if (field != widget.currentSort.field) return label;
    final suffix = widget.currentSort.direction == TicketSortDirection.ascending
        ? context.l10n.ticketsListSortDirectionAscendingSemantics
        : context.l10n.ticketsListSortDirectionDescendingSemantics;
    return '$label$suffix';
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);

    _overlayEntry = OverlayEntry(
      builder: (context) {
        final t = ThemeScope.of(context);
        final c = t.colors;

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
                        child: ClipRRect(
                          borderRadius: BorderRadius.all(AionRadius.lg),
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final field in TicketSortField.values)
                                    _SortRow(
                                      field: field,
                                      isActive:
                                          field == widget.currentSort.field,
                                      direction: widget.currentSort.direction,
                                      enabled:
                                          field != TicketSortField.relevance ||
                                          widget.hasActiveQuery,
                                      autofocus:
                                          field == widget.currentSort.field,
                                      semanticsLabel: _rowSemanticsLabel(
                                        context,
                                        field,
                                      ),
                                      onTap: () => _handleTap(field),
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

/// One [TicketSortField] row inside [TicketSortPopover]'s open panel.
/// Manages its own hover/focus/pressed visual state — active and
/// inactive rows use different fill formulas (an active row's resting
/// fill is already `c.primarySubtle`-tinted, unlike
/// `OverlayMenuItem`'s plain transparent→`surfaceHover`→`border`
/// progression), so this doesn't reuse `OverlayMenuItem` directly.
class _SortRow extends StatefulWidget {
  const _SortRow({
    required this.field,
    required this.isActive,
    required this.direction,
    required this.enabled,
    required this.autofocus,
    required this.semanticsLabel,
    required this.onTap,
  });

  /// The field this row represents.
  final TicketSortField field;

  /// Whether [field] is the currently active sort field.
  final bool isActive;

  /// The active sort's direction — only rendered (as the trailing
  /// direction glyph) when [isActive] is `true`.
  final TicketSortDirection direction;

  /// Whether this row can be hovered, focused, or activated. `false`
  /// only for the [TicketSortField.relevance] row when no search query
  /// is active (see [TicketSortPopover.hasActiveQuery]).
  final bool enabled;

  /// Whether this row should claim keyboard focus as soon as the popover
  /// opens — `true` for the currently active row.
  final bool autofocus;

  /// Announced by `Semantics(button: true)`.
  final String semanticsLabel;

  /// Called on tap, `Enter`, or `Space`. Not called when [enabled] is
  /// `false`.
  final VoidCallback onTap;

  @override
  State<_SortRow> createState() => _SortRowState();
}

class _SortRowState extends State<_SortRow> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  void _setHovered(bool value) {
    if (widget.enabled) setState(() => _isHovered = value);
  }

  void _setPressed(bool value) {
    if (widget.enabled) setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final hoverAlpha = t.isDark ? fillAlphaObsidian : fillAlphaArctic;

    final Color fill;
    if (!widget.enabled) {
      fill = const Color(0x00000000);
    } else if (_isPressed) {
      fill = widget.isActive
          ? Color.alphaBlend(
              c.primary.withValues(alpha: hoverAlpha * 1.4),
              c.primarySubtle,
            )
          : c.border;
    } else if (_isHovered || _isFocused) {
      fill = widget.isActive
          ? Color.alphaBlend(
              c.primary.withValues(alpha: hoverAlpha),
              c.primarySubtle,
            )
          : c.surfaceHover;
    } else if (widget.isActive) {
      fill = c.primarySubtle;
    } else {
      fill = const Color(0x00000000);
    }

    final labelColor = !widget.enabled
        ? c.textMuted
        : (widget.isActive ? c.primary : c.textPrimary);

    final boxShadow = widget.enabled && _isFocused
        ? [
            BoxShadow(
              color: c.primary.withValues(alpha: t.isDark ? 0.30 : 0.16),
              spreadRadius: 2,
            ),
          ]
        : const <BoxShadow>[];

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: _leadingSwatch(context, widget.field),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ticketSortFieldLabel(context, widget.field),
              style: AionText.bodySm.copyWith(color: labelColor),
            ),
          ),
          if (widget.isActive)
            PhosphorIcon(
              widget.direction == TicketSortDirection.ascending
                  ? PhosphorIcons.arrowUpLight
                  : PhosphorIcons.arrowDownLight,
              size: 12,
              color: c.primary,
            ),
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticsLabel,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: FocusableActionDetector(
          enabled: widget.enabled,
          autofocus: widget.autofocus,
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
            onTap: widget.enabled ? widget.onTap : null,
            onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
            onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
            onTapCancel: widget.enabled ? () => _setPressed(false) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              decoration: BoxDecoration(color: fill, boxShadow: boxShadow),
              child: widget.enabled ? row : Opacity(opacity: 0.5, child: row),
            ),
          ),
        ),
      ),
    );
  }
}

/// The leading accent swatch shown before Priority/Status/Type rows'
/// labels — a small decorative field glyph identifying the field, not a
/// value selector. `null` (no swatch, just the reserved 10×10 leading
/// space [_SortRow] always allocates) for Relevance/Created/Last-updated
/// rows.
Widget? _leadingSwatch(BuildContext context, TicketSortField field) {
  final c = ThemeScope.of(context).colors;
  return switch (field) {
    TicketSortField.priority => _AccentShape.dot(c.priority.criticalFg),
    TicketSortField.status => _AccentShape.dot(c.primary),
    TicketSortField.type => _AccentShape.square(c.typeTask),
    TicketSortField.relevance ||
    TicketSortField.createdAt ||
    TicketSortField.updatedAt => null,
  };
}

/// A small decorative accent shape for [_leadingSwatch] — either an 8×8
/// circle ([_AccentShape.dot]) or a 10×10, `radius: 2` rounded square
/// ([_AccentShape.square]), in [color].
class _AccentShape extends StatelessWidget {
  const _AccentShape._({required this.color, required this.isSquare});

  /// An 8×8 circular accent dot (the Priority/Status rows' shape).
  factory _AccentShape.dot(Color color) =>
      _AccentShape._(color: color, isSquare: false);

  /// A 10×10, `radius: 2` rounded-square accent (the Type row's shape).
  factory _AccentShape.square(Color color) =>
      _AccentShape._(color: color, isSquare: true);

  /// The shape's fill color.
  final Color color;

  /// Whether this renders as a rounded square (`true`) or a circle
  /// (`false`).
  final bool isSquare;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: isSquare ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: isSquare ? BorderRadius.circular(2) : null,
      ),
      child: SizedBox(width: isSquare ? 10 : 8, height: isSquare ? 10 : 8),
    );
  }
}

/// Returns the display label for [field] (e.g. `"Priority"`, `"Last
/// updated"`). One-place mapping, same rationale as
/// `ticketTypeLabel`/`ticketStatusLabel`/`ticketPriorityLabel`
/// (`tickets_board_view.dart`) — shared by [TicketSortPopover]'s own rows
/// and `_SortTriggerButton`'s active-field label
/// (`tickets_list_screen.dart`).
String ticketSortFieldLabel(BuildContext context, TicketSortField field) {
  final l10n = context.l10n;
  return switch (field) {
    TicketSortField.relevance => l10n.ticketsListSortFieldRelevance,
    TicketSortField.priority => l10n.ticketsListSortFieldPriority,
    TicketSortField.status => l10n.ticketsListSortFieldStatus,
    TicketSortField.type => l10n.ticketsListSortFieldType,
    TicketSortField.createdAt => l10n.ticketsListSortFieldCreatedAt,
    TicketSortField.updatedAt => l10n.ticketsListSortFieldUpdatedAt,
  };
}
