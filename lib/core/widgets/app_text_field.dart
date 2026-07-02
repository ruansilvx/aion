import 'package:flutter/material.dart'
    show Material, MaterialType, TextField, InputDecoration, OutlineInputBorder;
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';

import 'package:aion/core/theme/aion_radius.dart';
import 'package:aion/core/theme/aion_shadows.dart';
import 'package:aion/core/theme/aion_text.dart';
import 'package:aion/core/theme/theme_scope.dart';

class AppTextField extends StatefulWidget {
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
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? labelText;
  final String? hintText;
  final int maxLines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool isRequired;
  final bool isOptional;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  FocusNode? _ownedFocusNode;
  bool _isFocused = false;

  FocusNode get _focusNode => widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

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
    final isMultiline = widget.maxLines > 1;

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
                  Text(' *', style: AionText.label.copyWith(color: c.danger)),
                if (widget.isOptional)
                  Text(
                    '  Optional',
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
                  : AionText.bodySm.copyWith(color: c.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                fillColor: c.surface,
                filled: true,
                isDense: true,
                isCollapsed: false,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
