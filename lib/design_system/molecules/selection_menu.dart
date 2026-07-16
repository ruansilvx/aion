// design_system/molecules/selection_menu.dart — SelectionMenu<T> generic overlay picker (design-system layer).

import 'package:flutter/widgets.dart';

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
              offset: const Offset(0, 6),
              targetAnchor: Alignment.bottomLeft,
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
                        child: Text(
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
          child: GestureDetector(onTap: _toggleOverlay, child: widget.trigger),
        ),
      ),
    );
  }
}
