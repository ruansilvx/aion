// design_system/atoms/app_text_field.dart — AppTextField primitive widget (design-system layer).

import 'package:flutter/material.dart'
    show Material, MaterialType, TextField, InputDecoration, OutlineInputBorder;
import 'package:flutter/services.dart'
    show TextInputAction, TextInputType, TextInputFormatter;
import 'package:flutter/widgets.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/tokens/aion_colors.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_shadows.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';

/// Aion's text-field primitive — an optional label above a token-styled
/// input. Wraps Flutter's `TextField` (the one Material widget permitted in
/// the widget layer, see design.md's Material Coupling Audit) with every
/// `InputDecoration` value supplied explicitly from [AionColors]/[AionText]
/// tokens, and a transparent [Material] ancestor since `TextField` requires
/// one even outside `MaterialApp`. [obscureText]/[suffixIcon]/[isError] are
/// additive (default `false`/`null`/`false`) — added so a secret-entry
/// field (e.g. an API key) can mask its value with a reveal toggle and
/// show a validation-error border, without a bespoke widget; every
/// existing call site is unaffected. See
/// `aion-arch/changes/anthropic-messages-api-provider/design.md` §9.
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
    this.keyboardType,
    this.inputFormatters,
    this.obscureText = false,
    this.suffixIcon,
    this.isError = false,
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
  /// greater renders the multiline style with a 5-line minimum height, or
  /// [maxLines] itself as the minimum when it's set below 5 (so a caller
  /// can request a genuinely short multiline field — e.g. 3 or 4 lines —
  /// without violating `TextField`'s own `minLines <= maxLines`
  /// invariant). `null` renders the multiline style with no upper bound
  /// (an unbounded/expanding textarea), passed through to the underlying
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

  /// Which on-screen keyboard variant to show (e.g. `TextInputType.number`
  /// for a numeric-only field). `null` uses `TextField`'s own default.
  final TextInputType? keyboardType;

  /// Input formatters applied to every keystroke (e.g.
  /// `FilteringTextInputFormatter.digitsOnly`). `null` applies none.
  final List<TextInputFormatter>? inputFormatters;

  /// Masks the entered text (`•` per character) when `true` — used for
  /// secret-entry fields like an API key. Passed straight through to the
  /// wrapped `TextField.obscureText`; default `false` preserves every
  /// existing call site's plaintext rendering.
  final bool obscureText;

  /// Optional trailing icon shown inside the field, after the text (e.g.
  /// a reveal/hide toggle for an [obscureText] field). Styling and
  /// interactivity are the caller's responsibility — this widget renders
  /// whatever is passed as-is via `InputDecoration.suffixIcon`, mirroring
  /// [prefixIcon]'s existing contract.
  final Widget? suffixIcon;

  /// Renders the field in its validation-error state — a `1.5px`
  /// [AionColors.danger] border plus an [AionColorsHubTokens.errorRing]
  /// focus-style ring, regardless of hover/focus. The caller owns the
  /// validation logic and any error text shown alongside this field (this
  /// widget renders no error copy itself, matching `NewProjectScreen`'s
  /// existing hand-rolled error-field pattern). Default `false` preserves
  /// every existing call site's rendering.
  final bool isError;

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
    // [obscureText] forces the field back to single-line regardless of
    // [maxLines] (see the `TextField.maxLines` line below) — computed here
    // too so `isMultiline`/`minLines` agree with what's actually rendered
    // rather than with the un-overridden [maxLines] value alone.
    final effectiveMaxLines = widget.obscureText ? 1 : widget.maxLines;
    final isMultiline = effectiveMaxLines == null || effectiveMaxLines > 1;
    // A 5-line minimum height for any multiline field, capped at
    // [effectiveMaxLines] itself when that's fewer than 5 — `TextField`
    // asserts `minLines <= maxLines`, so a caller-supplied [maxLines] below
    // 5 (e.g. `AgentPromptField`'s 4-line prompt, per
    // `aion-arch/changes/decision-graph-agentjudgment-condition/design.md`
    // §2.1) must not be handed a fixed `minLines: 5` — that combination
    // throws immediately. Fixed as part of that change's `/verify` pass;
    // pre-existing bare `AppTextField(maxLines: 3)` call sites
    // (`raise_gap_or_question_picker.dart`, `create_ticket_screen.dart`)
    // shared the same latent crash before this fix.
    final minLines = isMultiline
        ? (effectiveMaxLines == null || effectiveMaxLines >= 5
              ? 5
              : effectiveMaxLines)
        : 1;

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
            boxShadow: widget.isError
                ? [
                    BoxShadow(
                      color: c.errorRing(t.isDark),
                      spreadRadius: 3,
                    ),
                  ]
                : (_isFocused ? AionShadows.focus(c, t.isDark) : const []),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              maxLines: effectiveMaxLines,
              minLines: minLines,
              obscureText: widget.obscureText,
              keyboardType: widget.keyboardType,
              inputFormatters: widget.inputFormatters,
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
                suffixIcon: widget.suffixIcon,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                hintText: widget.hintText,
                hintStyle: (isMultiline ? AionText.body : AionText.bodySm)
                    .copyWith(color: c.textMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(AionRadius.lg),
                  borderSide: widget.isError
                      ? BorderSide(color: c.danger, width: 1.5)
                      : BorderSide(color: c.border, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(AionRadius.lg),
                  borderSide: widget.isError
                      ? BorderSide(color: c.danger, width: 1.5)
                      : BorderSide(color: c.border, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(AionRadius.lg),
                  borderSide: widget.isError
                      ? BorderSide(color: c.danger, width: 1.5)
                      : BorderSide(color: c.primary, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
