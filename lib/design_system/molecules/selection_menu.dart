// design_system/molecules/selection_menu.dart — SelectionMenu<T> generic overlay picker (design-system layer).

import 'package:flutter/widgets.dart';

import 'package:aion/design_system/tokens/aion_colors.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_shadows.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';

/// A generic overlay-picker primitive: [trigger] stays visible at all
/// times, and tapping it (or activating it via keyboard) opens an
/// [Overlay] listing [items] (excluding [currentValue] — re-offering the
/// already-selected value is a wasted tap). Selecting one calls
/// [onSelected] and dismisses the overlay.
///
/// Generalizes the overlay/[LayerLink]/[CompositedTransformFollower]
/// mechanics `MoveToStatusMenu` (`tickets_board_view.dart`) already
/// established for the board's status picker, so ticket-detail's
/// priority/type editors don't need a third bespoke copy of the same
/// pattern. `MoveToStatusMenu` itself is untouched — it predates this
/// widget and isn't refactored to use it in this change.
class SelectionMenu<T> extends StatefulWidget {
  /// Creates a [SelectionMenu].
  const SelectionMenu({
    super.key,
    required this.trigger,
    required this.items,
    required this.itemLabel,
    required this.currentValue,
    required this.onSelected,
    required this.semanticsLabel,
    this.openUpward = false,
    this.onOpenChanged,
    this.onFocusChange,
    this.itemBuilder,
  });

  /// The always-visible tappable widget (e.g. a `PriorityBadge`/`TypeChip`).
  final Widget trigger;

  /// The full set of selectable values. [currentValue] is filtered out of
  /// the rendered overlay list automatically.
  final List<T> items;

  /// Converts a value of type [T] to its display string.
  final String Function(T) itemLabel;

  /// The currently selected value — excluded from the overlay's options.
  final T currentValue;

  /// Called with the newly selected value when the user picks an item.
  final ValueChanged<T> onSelected;

  /// Accessibility label describing what this menu changes (e.g.
  /// `'Change priority'`).
  final String semanticsLabel;

  /// Opens the overlay above [trigger] instead of below it — for a
  /// trigger anchored near the bottom of the viewport (e.g.
  /// `WorkspaceNavShell`'s secondary-actions trigger), where the default
  /// downward placement would render off-screen. Defaults to `false`
  /// (downward), preserving every existing caller's behavior.
  final bool openUpward;

  /// Called with `true` when the overlay opens and `false` when it
  /// closes — lets [trigger] reflect open state visually (e.g. holding a
  /// focus-ring look while its own popover is up). Optional; existing
  /// callers that don't need this stay unaffected.
  final ValueChanged<bool>? onOpenChanged;

  /// Called when this menu's own [FocusableActionDetector] gains or
  /// loses keyboard focus highlight — lets a stateful [trigger] render
  /// its own focus ring without introducing a second, competing
  /// focusable region nested inside [trigger] itself. Optional; existing
  /// callers that don't need this stay unaffected.
  final ValueChanged<bool>? onFocusChange;

  /// Builds a menu row's content for [item], overriding the default
  /// plain [itemLabel] text row — used by pickers whose design (e.g. the
  /// Complexity meter/sub-hint, the Automation-Confidence mode dot/
  /// sub-label, per
  /// `aion-arch/changes/sdd-ticket-execution/design.md` §1.4/§6.3) needs
  /// more than a label per row. Every pre-existing caller omits this and
  /// keeps the plain-text row unchanged.
  final Widget Function(BuildContext context, AionColors c, T item)?
  itemBuilder;

  @override
  State<SelectionMenu<T>> createState() => _SelectionMenuState<T>();
}

class _SelectionMenuState<T> extends State<SelectionMenu<T>> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

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

  void _showOverlay() {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final overlay = Overlay.of(context);
    final selectable = widget.items
        .where((i) => i != widget.currentValue)
        .toList();

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
              offset: widget.openUpward
                  ? const Offset(0, -6)
                  : const Offset(0, 6),
              targetAnchor: widget.openUpward
                  ? Alignment.topLeft
                  : Alignment.bottomLeft,
              followerAnchor: widget.openUpward
                  ? Alignment.bottomLeft
                  : Alignment.topLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.all(AionRadius.lg),
                  border: Border.all(color: c.borderStrong, width: 1),
                  boxShadow: AionShadows.card(c, t.isDark),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: selectable.map((item) {
                    final builder = widget.itemBuilder;
                    return GestureDetector(
                      onTap: () {
                        widget.onSelected(item);
                        _removeOverlay();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 9,
                          horizontal: 13,
                        ),
                        child: builder != null
                            ? builder(context, c, item)
                            : Text(
                                widget.itemLabel(item),
                                style: AionText.bodySm.copyWith(
                                  color: c.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    );
                  }).toList(),
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

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    // Guards against setState-after-dispose: the same class of bug
    // project.md's AppDropdown overlay-dismiss crash note warns about.
    if (mounted) {
      setState(() => _isOpen = false);
    } else {
      _isOpen = false;
    }
    widget.onOpenChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Semantics(
        button: true,
        label: widget.semanticsLabel,
        child: FocusableActionDetector(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _toggleOverlay();
                return null;
              },
            ),
          },
          onShowFocusHighlight: widget.onFocusChange,
          child: GestureDetector(onTap: _toggleOverlay, child: widget.trigger),
        ),
      ),
    );
  }
}
