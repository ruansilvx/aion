// design_system/atoms/app_text_field.dart — AppTextField primitive widget (design-system layer).

import 'package:flutter/material.dart'
    show Material, MaterialType, TextField, InputDecoration, OutlineInputBorder;
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_shadows.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';

/// Aion's text-field primitive — an optional label above a token-styled
/// input. Wraps Flutter's `TextField` (the one Material widget permitted in
/// the widget layer, see design.md's Material Coupling Audit) with every
/// `InputDecoration` value supplied explicitly from [AionColors]/[AionText]
/// tokens, and a transparent [Material] ancestor since `TextField` requires
/// one even outside `MaterialApp`.
class AppTextField extends StatefulWidget {
  /// Creates an [AppTextField].
  const AppTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.labelText,
    this.hintText,
    this.maxLines = 1,
    this.textInputAction,
    this.onSubmitted,
    this.isRequired = false,
    this.isOptional = false,
    this.prefixIcon,
  });

  /// Controls and reads the field's text.
  final TextEditingController controller;

  /// Optional focus node for keyboard/tab navigation. If omitted, an
  /// internal one is created and disposed automatically.
  final FocusNode? focusNode;

  /// Optional label rendered above the field.
  final String? labelText;

  /// Placeholder text shown when [controller] is empty.
  final String? hintText;

  /// Number of visible lines. `1` renders the single-line style; anything
  /// greater renders the multiline style with a 5-line minimum height.
  /// `null` renders the multiline style with no upper bound (an
  /// unbounded/expanding textarea), passed through to the underlying
  /// `TextField` as-is — Flutter's `TextField` already supports
  /// `maxLines: null` natively.
  final int? maxLines;

  /// Which action the on-screen keyboard's action key performs.
  final TextInputAction? textInputAction;

  /// Called when the field is submitted (e.g. via the keyboard action key).
  final ValueChanged<String>? onSubmitted;

  /// Whether to render a required-field marker (`*`) next to [labelText].
  final bool isRequired;

  /// Whether to render an "Optional" marker next to [labelText].
  final bool isOptional;

  /// Optional leading icon shown inside the field, before the text. Color
  /// and any per-state styling are the caller's responsibility — this
  /// widget renders whatever is passed as-is via [InputDecoration.prefixIcon].
  final Widget? prefixIcon;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  FocusNode? _ownedFocusNode;
  bool _isFocused = false;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() => _isFocused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isMultiline = widget.maxLines == null || widget.maxLines! > 1;

    return Column(
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
                if (widget.isOptional)
                  Text(
                    context.l10n.commonOptionalMarker,
                    style: AionText.bodySm.copyWith(
                      color: c.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.all(AionRadius.lg),
            boxShadow: _isFocused ? AionShadows.focus(c, t.isDark) : const [],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              maxLines: widget.maxLines,
              minLines: isMultiline ? 5 : 1,
              textInputAction: widget.textInputAction,
              onSubmitted: widget.onSubmitted,
              textAlignVertical: isMultiline ? TextAlignVertical.top : null,
              style: isMultiline
                  ? AionText.body.copyWith(color: c.textPrimary)
                  : AionText.bodySm.copyWith(
                      color: c.textPrimary,
                      fontSize: 14,
                    ),
              decoration: InputDecoration(
                fillColor: c.surface,
                filled: true,
                isDense: true,
                isCollapsed: false,
                prefixIcon: widget.prefixIcon,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                hintText: widget.hintText,
                hintStyle: (isMultiline ? AionText.body : AionText.bodySm)
                    .copyWith(color: c.textMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(AionRadius.lg),
                  borderSide: BorderSide(color: c.border, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(AionRadius.lg),
                  borderSide: BorderSide(color: c.border, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(AionRadius.lg),
                  borderSide: BorderSide(color: c.primary, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
