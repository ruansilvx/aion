// presentation/widgets/chat_compose_field.dart — ChatComposeField auto-expanding compose input (presentation layer).

import 'package:flutter/material.dart'
    show Material, MaterialType, TextField, InputDecoration;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';

/// The chat compose field — an auto-expanding multiline text input
/// (starts at one line, grows to a capped height, then scrolls
/// internally) with Enter-to-send / Shift+Enter-for-newline on hardware
/// keyboards, replacing the fixed single-line pill used for plain
/// ticket comments. Not built on [AppTextField]: that widget's
/// multiline mode forces a 5-line minimum height and an outlined-box
/// shape, neither of which fits a compose bar that should start at one
/// line — this wraps `TextField` directly instead, the same sanctioned
/// exception to the no-Material-widgets rule [AppTextField] relies on.
/// Per `AIO-482` §3.
class ChatComposeField extends StatefulWidget {
  /// Creates a [ChatComposeField] backed by [controller], calling
  /// [onSend] when the user sends the current text.
  const ChatComposeField({
    super.key,
    required this.controller,
    required this.onSend,
  });

  /// Controls and reads the field's text.
  final TextEditingController controller;

  /// Called when the user sends — via the send button, or Enter without
  /// Shift on a hardware keyboard.
  final VoidCallback onSend;

  @override
  State<ChatComposeField> createState() => _ChatComposeFieldState();
}

class _ChatComposeFieldState extends State<ChatComposeField> {
  final _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() => _isFocused = _focusNode.hasFocus);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    widget.onSend();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: c.secondary, shape: BoxShape.circle),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Center(
              child: Text(
                'U',
                style: AionText.key.copyWith(color: const Color(0xFFFFFFFF)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(maxHeight: 128, minHeight: 44),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              border: Border.all(
                color: _isFocused ? c.primary : c.border,
                width: _isFocused ? 1.5 : 1,
              ),
              boxShadow: _isFocused ? AionShadows.focus(c, t.isDark) : const [],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Material(
                type: MaterialType.transparency,
                child: Focus(
                  onKeyEvent: _handleKeyEvent,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    maxLines: null,
                    minLines: 1,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: AionText.bodySm.copyWith(
                      color: c.textPrimary,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                    cursorColor: c.primary,
                    decoration: InputDecoration.collapsed(
                      hintText: context.l10n.ticketDetailChatComposeHint,
                      hintStyle: AionText.bodySm.copyWith(
                        color: c.textMuted,
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _SendButton(controller: widget.controller, onSend: widget.onSend),
      ],
    );
  }
}

/// The circular send button — idle when [controller] is empty, active
/// (`primary` fill + glow) otherwise, with hover/pressed states. Design.md
/// §3.3.
class _SendButton extends StatefulWidget {
  const _SendButton({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  final ValueNotifier<bool> _isHovered = ValueNotifier(false);
  bool _isPressed = false;

  @override
  void dispose() {
    _isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final isActive = value.text.trim().isNotEmpty;
        return Semantics(
          button: true,
          label: context.l10n.ticketDetailSendComment,
          enabled: isActive,
          child: MouseRegion(
            cursor: isActive ? SystemMouseCursors.click : MouseCursor.defer,
            onEnter: (_) => _isHovered.value = true,
            onExit: (_) => _isHovered.value = false,
            child: GestureDetector(
              onTap: isActive ? widget.onSend : null,
              onTapDown: isActive
                  ? (_) => setState(() => _isPressed = true)
                  : null,
              onTapUp: isActive
                  ? (_) => setState(() => _isPressed = false)
                  : null,
              onTapCancel: isActive
                  ? () => setState(() => _isPressed = false)
                  : null,
              child: ValueListenableBuilder<bool>(
                valueListenable: _isHovered,
                builder: (context, hovered, _) {
                  final fill = !isActive
                      ? c.surfaceHover
                      : (hovered ? c.primaryHover : c.primary);
                  return AnimatedScale(
                    scale: isActive && _isPressed ? 0.92 : 1.0,
                    duration: const Duration(milliseconds: 80),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(19),
                        boxShadow: isActive
                            ? AionShadows.fab(c, t.isDark)
                            : const [],
                      ),
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: Center(
                          child: PhosphorIcon(
                            PhosphorIcons.paperPlaneTiltLight,
                            size: 17,
                            color: isActive
                                ? const Color(0xFFFFFFFF)
                                : c.textMuted,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
