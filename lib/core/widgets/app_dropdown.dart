// core/widgets/app_dropdown.dart — AppDropdown primitive widget (core layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/localization/context_localizations_x.dart';
import 'package:aion/core/theme/aion_radius.dart';
import 'package:aion/core/theme/aion_shadows.dart';
import 'package:aion/core/theme/aion_text.dart';
import 'package:aion/core/theme/theme_scope.dart';

/// Aion's dropdown/select primitive — replaces `DropdownButton` with a
/// tap target that opens an [OverlayEntry] of selectable items. No Material
/// widget or overlay involvement.
class AppDropdown<T> extends StatefulWidget {
  /// Creates an [AppDropdown].
  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.itemLabel,
    this.labelText,
    this.semanticsLabel,
    this.isRequired = false,
    this.focusNode,
    this.isActive = false,
  });

  /// The currently selected value. Must be one of [items].
  final T value;

  /// The full list of selectable values.
  final List<T> items;

  /// Called with the newly selected value when the user picks an item.
  final ValueChanged<T> onChanged;

  /// Converts a value of type [T] to its display string.
  final String Function(T) itemLabel;

  /// Optional label rendered above the field.
  final String? labelText;

  /// Optional label used only for the accessibility announcement
  /// (`Semantics.label`), without rendering a visible caption above the
  /// field. Falls back to [labelText], then to no label, when unset. Use
  /// this when the visible design intentionally omits a caption (e.g. a
  /// compact filter row) but the control still needs to announce what it
  /// filters to assistive technology.
  final String? semanticsLabel;

  /// Whether to render a required-field marker next to [labelText].
  final bool isRequired;

  /// Optional focus node for keyboard/tab navigation. If omitted, an
  /// internal one is created and disposed automatically.
  final FocusNode? focusNode;

  /// Whether [value] represents an active, non-default selection (as
  /// opposed to a "cleared"/reset sentinel among [items]). When `true`,
  /// the closed trigger renders with a tinted `primarySubtle` fill, a
  /// `primary`-colored border and text, and a small leading dot — letting
  /// a user see at a glance that this control is narrowing something,
  /// without needing it open. Purely a caller-driven presentation flag;
  /// this widget has no concept of which [items] value counts as
  /// "default."
  final bool isActive;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  FocusNode? _ownedFocusNode;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _ownedFocusNode?.dispose();
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
              offset: const Offset(0, 4),
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
                  children: widget.items.map((item) {
                    final selected = item == widget.value;
                    return GestureDetector(
                      onTap: () {
                        widget.onChanged(item);
                        _removeOverlay();
                      },
                      child: Container(
                        color: selected ? c.primarySubtle : null,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 14,
                        ),
                        child: Text(
                          widget.itemLabel(item),
                          style: AionText.bodySm.copyWith(
                            color: selected ? c.primary : c.textPrimary,
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
    if (mounted) {
      setState(() => _isOpen = false);
    } else {
      _isOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final emphasized = _isOpen || widget.isActive;
    final emphasisColor = emphasized ? c.primary : null;

    return Semantics(
      button: true,
      label:
          '${widget.semanticsLabel ?? widget.labelText ?? ''} '
          '${widget.itemLabel(widget.value)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.labelText != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AionSpacing.sp4),
              child: Row(
                children: [
                  Text(
                    widget.labelText!,
                    style: AionText.label.copyWith(color: c.textSecondary),
                  ),
                  if (widget.isRequired)
                    Text(
                      context.l10n.commonRequiredMarker,
                      style: AionText.label.copyWith(color: c.danger),
                    ),
                ],
              ),
            ),
          CompositedTransformTarget(
            link: _layerLink,
            child: FocusableActionDetector(
              focusNode: _focusNode,
              child: GestureDetector(
                onTap: _toggleOverlay,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.isActive ? c.primarySubtle : c.surface,
                    borderRadius: BorderRadius.all(AionRadius.lg),
                    border: Border.all(
                      color: emphasisColor ?? c.border,
                      width: emphasized ? 1.5 : 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        if (widget.isActive) ...[
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox(width: 6, height: 6),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            widget.itemLabel(widget.value),
                            style: AionText.bodySm.copyWith(
                              color: emphasisColor ?? c.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        PhosphorIcon(
                          _isOpen
                              ? PhosphorIcons.caretUpLight
                              : PhosphorIcons.caretDownLight,
                          size: 12,
                          color: emphasisColor ?? c.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
