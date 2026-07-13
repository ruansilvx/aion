// features/tickets/presentation/widgets/inline_editable_field.dart — InlineEditableField<T> tap-to-edit primitive (presentation layer).

import 'package:flutter/services.dart' show LogicalKeyboardKey, TextInputAction;
import 'package:flutter/widgets.dart';

import 'package:aion/core/theme/aion_radius.dart';
import 'package:aion/core/theme/aion_text.dart';
import 'package:aion/core/theme/theme_scope.dart';
import 'package:aion/core/widgets/app_button.dart';
import 'package:aion/core/widgets/app_text_field.dart';
import 'package:aion/core/widgets/app_toast.dart';

/// Cancels an in-progress [InlineEditableField] edit. Dispatched via
/// [Shortcuts]/[Actions] (not a directly-attached [FocusNode] listener)
/// so it composes safely with the [AppTextField] already occupying the
/// focus node underneath it.
class _CancelEditIntent extends Intent {
  const _CancelEditIntent();
}

/// A tap-to-edit field: view mode renders [displayText] (or a muted
/// [placeholder] when empty); activating it (tap, or Enter/Space via
/// keyboard focus) swaps in a text box pre-filled with [editText].
///
/// Single-line fields ([maxLines] `== 1`) commit on Enter or on losing
/// focus. Multiline fields commit only via an explicit Save/Cancel row
/// shown while editing — never on blur alone, since losing focus while
/// scrolling a long field is too easy to trigger by accident.
///
/// Committing runs [parser] against the raw text; on success calls
/// [onCommit] with the parsed value and returns to view mode. If [parser]
/// throws a [FormatException], shows an [AppToast] with its message,
/// reverts to [editText], and returns to view mode without calling
/// [onCommit]. `Escape` cancels an in-progress edit (reverts, exits)
/// without ever calling [parser].
///
/// Reused for title, description, estimate, and time spent on
/// `TicketDetailScreen` — the generic [T] and [parser]/[onCommit]
/// callbacks let one widget serve all four fields.
class InlineEditableField<T> extends StatefulWidget {
  /// Creates an [InlineEditableField].
  const InlineEditableField({
    super.key,
    required this.displayText,
    required this.editText,
    required this.parser,
    required this.onCommit,
    required this.semanticsLabel,
    this.placeholder,
    this.maxLines = 1,
    this.textStyle,
  });

  /// What to render in view mode when non-empty.
  final String displayText;

  /// Pre-fill text when entering edit mode.
  final String editText;

  /// Parses the raw text box contents into [T]. May throw
  /// [FormatException] for invalid input — caught by this widget,
  /// surfaced via [AppToast], and reverted; never reaches [onCommit].
  final T Function(String raw) parser;

  /// Called with the parsed value once validation succeeds.
  final ValueChanged<T> onCommit;

  /// Accessibility label for the view-mode tap target.
  final String semanticsLabel;

  /// Muted placeholder text shown instead of [displayText] when it's empty.
  final String? placeholder;

  /// Number of visible lines. `1` is single-line (commits on Enter or
  /// blur); anything greater is multiline (commits via Save/Cancel only).
  final int maxLines;

  /// Text style used for both view and edit mode. Defaults to
  /// [AionText.body].
  final TextStyle? textStyle;

  @override
  State<InlineEditableField<T>> createState() => _InlineEditableFieldState<T>();
}

class _InlineEditableFieldState<T> extends State<InlineEditableField<T>> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isEditing = false;

  bool get _isMultiline => widget.maxLines > 1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.editText);
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    // Single-line fields commit on blur. Multiline fields commit only via
    // the explicit Save button — blur alone (e.g. while scrolling a long
    // description) must not trigger a save.
    if (!_focusNode.hasFocus && _isEditing && !_isMultiline) {
      _commit();
    }
  }

  void _enterEditMode() {
    _controller.text = widget.editText;
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _cancel() {
    _controller.text = widget.editText;
    if (!mounted) return;
    setState(() => _isEditing = false);
  }

  void _commit() {
    final raw = _controller.text;
    final T parsed;
    try {
      parsed = widget.parser(raw);
    } on FormatException catch (e) {
      AppToast.show(context, e.message);
      _controller.text = widget.editText;
      if (mounted) setState(() => _isEditing = false);
      return;
    }
    if (!mounted) return;
    setState(() => _isEditing = false);
    widget.onCommit(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final style = widget.textStyle ?? AionText.body;

    final Widget child;
    if (_isEditing) {
      final editor = Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): _CancelEditIntent(),
        },
        child: Actions(
          actions: {
            _CancelEditIntent: CallbackAction<_CancelEditIntent>(
              onInvoke: (_) {
                _cancel();
                return null;
              },
            ),
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: widget.maxLines,
                textInputAction: _isMultiline ? TextInputAction.newline : TextInputAction.done,
                onSubmitted: _isMultiline ? null : (_) => _commit(),
              ),
              if (_isMultiline) ...[
                const SizedBox(height: AionSpacing.sp8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppButton(label: 'Cancel', variant: AppButtonVariant.ghost, onPressed: _cancel),
                    const SizedBox(width: AionSpacing.sp12),
                    AppButton(label: 'Save', variant: AppButtonVariant.primary, onPressed: _commit),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
      // Single-line fields are also used inside Row/min-width-Column
      // layouts (e.g. the estimate/time-spent meta row), which hand down
      // an unbounded width constraint. View-mode Text tolerates that, but
      // TextField's InputDecorator asserts against it, so this only
      // surfaces once a field is tapped into edit mode. IntrinsicWidth
      // sizes the field to its content instead of relying on the ambient
      // constraint.
      child = _isMultiline ? editor : IntrinsicWidth(child: editor);
    } else {
      final isEmpty = widget.displayText.isEmpty;
      final text = isEmpty ? (widget.placeholder ?? '') : widget.displayText;
      final color = isEmpty ? c.textMuted : style.color;

      // No hover-driven state here (no DecoratedBox fill, no pencil icon):
      // MouseRegion/FocusableActionDetector's hover callback fires from
      // inside Flutter's own MouseTracker device-update dispatch, and a
      // setState from within it that changes the widget subtree (e.g.
      // conditionally showing an icon) can re-enter MouseTracker's device
      // update while it's still mid-update — a real, reproducible Flutter
      // web crash (`!_debugDuringDeviceUpdate`), not just a theoretical
      // risk. The hover cue is decorative; cursor + Semantics already
      // signal "tappable" without touching hover state at all.
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _enterEditMode,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AionSpacing.sp8,
            vertical: AionSpacing.sp4,
          ),
          child: Text(text, style: style.copyWith(color: color)),
        ),
      );
    }

    // A single, structurally-stable outer wrapper across both modes — not
    // one FocusableActionDetector per mode. Swapping between two different
    // RenderObjects while the pointer is still over that exact spot
    // (guaranteed here, since a tap is what triggers the mode switch) can
    // crash Flutter's MouseTracker. Keeping this wrapper constant and only
    // swapping its child avoids that.
    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: FocusableActionDetector(
        actions: _isEditing
            ? const {}
            : {
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    _enterEditMode();
                    return null;
                  },
                ),
              },
        mouseCursor: SystemMouseCursors.text,
        child: child,
      ),
    );
  }
}
