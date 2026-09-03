// presentation/widgets/execution_cancel_control.dart — ExecutionCancelControl shared cancel affordance (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';

/// Where an [ExecutionCancelControl] renders — governs its chrome, not its
/// behavior (every placement calls [ExecutionCancelControl.onCancel] the same
/// way, with no confirmation dialog). See `AIO-1400` §2.
enum CancelPlacement {
  /// Icon-only, sized for `TicketsBoardView`'s `_CardVisual` status badge
  /// row — see `TicketsBoardView`'s `_CardVisual`.
  boardBadge,

  /// A labeled button, sized for the Task/Bug detail screen's execution-
  /// status section — see `ticket_detail_screen.dart`.
  detailButton,

  /// Icon-only, sized for `ChatTranscriptPane`'s `_StreamingBubble` —
  /// see that widget.
  chatStream,
}

/// One stop-square-glyph cancel affordance, shared by every
/// coding-execution/chat-reply cancellation surface in the app
/// ([CancelPlacement] picks the chrome) — a single widget so the three
/// placements can never visually drift apart. Danger-family hover/pressed
/// states, `AionColorsHubTokens.cancelFocusRing` for keyboard focus, no
/// confirmation dialog — cancelling is immediate on activation (tap or
/// Enter/Space while focused). No `IconButton`/`ElevatedButton`/`InkWell` —
/// built from `Focus`/`GestureDetector`/`DecoratedBox`, per this app's
/// no-Material constraint (mirrors `_RegenerateButton`'s own shape in
/// `ticket_metadata_section.dart`). Added for `AIO-1400`; see its linked
/// Documentation page, §2.
class ExecutionCancelControl extends StatefulWidget {
  /// Creates an [ExecutionCancelControl] for [placement], calling
  /// [onCancel] on activation. [semanticsLabel] overrides the default
  /// `"Cancel"` accessibility label — useful when [placement] needs a
  /// more specific label (e.g. naming the ticket being cancelled).
  const ExecutionCancelControl({
    super.key,
    required this.placement,
    required this.onCancel,
    this.semanticsLabel,
  });

  /// Which chrome variant to render.
  final CancelPlacement placement;

  /// Called on activation. Fires immediately — no confirmation dialog.
  final VoidCallback onCancel;

  /// Accessibility label; defaults to `context.l10n.commonCancel`.
  final String? semanticsLabel;

  @override
  State<ExecutionCancelControl> createState() =>
      _ExecutionCancelControlState();
}

class _ExecutionCancelControlState extends State<ExecutionCancelControl> {
  bool _isHovered = false;
  bool _isPressed = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isDark = t.isDark;

    final Color fill;
    final Color glyphColor;
    if (_isPressed) {
      fill = c.dangerTint(isDark);
      glyphColor = c.dangerText(isDark);
    } else if (_isHovered || _isFocused) {
      fill = c.dangerTint(isDark);
      glyphColor = c.danger;
    } else {
      fill = const Color(0x00000000);
      glyphColor = c.textMuted;
    }

    final glyphSize = widget.placement == CancelPlacement.detailButton
        ? 14.0
        : 13.0;
    final glyph = PhosphorIcon(
      PhosphorIconsBold.stop,
      size: glyphSize,
      color: glyphColor,
    );

    final label = widget.semanticsLabel ?? context.l10n.commonCancel;

    final Widget core = switch (widget.placement) {
      CancelPlacement.detailButton => DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: c.dangerBorderTint(isDark)),
          borderRadius: const BorderRadius.all(AionRadius.md),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: c.cancelFocusRing(isDark),
                    blurRadius: 0,
                    spreadRadius: 3,
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AionSpacing.sp12,
            vertical: AionSpacing.sp8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              glyph,
              const SizedBox(width: AionSpacing.sp8),
              Text(
                label,
                style: AionText.cardTitle.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: glyphColor,
                ),
              ),
            ],
          ),
        ),
      ),
      CancelPlacement.boardBadge || CancelPlacement.chatStream => DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: const BorderRadius.all(AionRadius.iconBtnSm),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: c.cancelFocusRing(isDark),
                    blurRadius: 0,
                    spreadRadius: 3,
                  ),
                ]
              : null,
        ),
        child: SizedBox(width: 22, height: 22, child: Center(child: glyph)),
      ),
    };

    return Semantics(
      button: true,
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: FocusableActionDetector(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onCancel();
                return null;
              },
            ),
          },
          onShowFocusHighlight: (value) => setState(() => _isFocused = value),
          child: GestureDetector(
            onTap: widget.onCancel,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: core,
          ),
        ),
      ),
    );
  }
}
