// core/widgets/app_confirm_dialog.dart — showAppConfirmDialog primitive (core layer).

import 'dart:async';

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/design_system.dart';
import 'package:aion/core/localization/context_localizations_x.dart';
import 'package:aion/core/widgets/app_button.dart';

/// Dismisses an open [showAppConfirmDialog] without confirming. Dispatched
/// via [Shortcuts]/[Actions] (not a directly-attached [FocusNode] listener),
/// matching `InlineEditableField`'s `_CancelEditIntent` pattern.
class _DismissConfirmDialogIntent extends Intent {
  const _DismissConfirmDialogIntent();
}

/// Shows a centered, non-Material confirmation dialog: a full-screen scrim
/// (dismiss on tap) behind a card with [title], [message], and a
/// Cancel/[confirmLabel] action row. Resolves `true` if the user confirms,
/// `false` if they cancel, tap the scrim, or press Escape.
///
/// Built the same way as [AppToast] — an [OverlayEntry] inserted into the
/// nearest [Overlay] — so it needs no `Scaffold`/`Dialog` ancestor and
/// stays outside the banned-Material-widgets list (no
/// `showDialog`/`AlertDialog`).
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  bool isDestructive = false,
}) {
  final t = ThemeScope.of(context);
  final c = t.colors;
  final overlay = Overlay.of(context);
  final resolvedCancelLabel = cancelLabel ?? context.l10n.commonCancel;
  final completer = _CompleterBox<bool>();
  late final OverlayEntry entry;

  void resolve(bool value) {
    completer.complete(value);
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) {
      return _AppConfirmDialogOverlay(
        colors: c,
        isDark: t.isDark,
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: resolvedCancelLabel,
        isDestructive: isDestructive,
        onResolve: resolve,
      );
    },
  );

  overlay.insert(entry);
  return completer.future;
}

/// Minimal box around a [Completer] so [showAppConfirmDialog] can complete
/// it exactly once regardless of which dismissal path (confirm, cancel,
/// scrim tap, Escape) fires first.
class _CompleterBox<T> {
  final Completer<T> _completer = Completer<T>();

  Future<T> get future => _completer.future;

  void complete(T value) {
    if (!_completer.isCompleted) {
      _completer.complete(value);
    }
  }
}

/// The overlay content built by [showAppConfirmDialog]: scrim, centered
/// card, and the Cancel/confirm action row. A separate widget (rather than
/// inline in the builder closure) purely to keep the `OverlayEntry.builder`
/// body readable.
class _AppConfirmDialogOverlay extends StatelessWidget {
  const _AppConfirmDialogOverlay({
    required this.colors,
    required this.isDark,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.isDestructive,
    required this.onResolve,
  });

  final AionColors colors;
  final bool isDark;
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDestructive;
  final ValueChanged<bool> onResolve;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < 420;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => onResolve(false),
            child: ColoredBox(
              color: const Color(
                0xFF000000,
              ).withValues(alpha: isDark ? 0.62 : 0.40),
            ),
          ),
        ),
        Center(
          child: GestureDetector(
            // Absorbs taps on the card itself so they don't bubble to the
            // full-screen scrim behind it and dismiss the dialog.
            onTap: () {},
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.escape):
                    _DismissConfirmDialogIntent(),
              },
              child: Actions(
                actions: {
                  _DismissConfirmDialogIntent:
                      CallbackAction<_DismissConfirmDialogIntent>(
                        onInvoke: (_) {
                          onResolve(false);
                          return null;
                        },
                      ),
                },
                child: Focus(
                  autofocus: true,
                  child: Semantics(
                    namesRoute: true,
                    label: title,
                    child: Container(
                      width: isNarrow ? width - AionSpacing.sp32 : 360,
                      padding: const EdgeInsets.all(AionSpacing.sp24),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border.all(color: colors.border, width: 1),
                        borderRadius: BorderRadius.all(AionRadius.xl),
                        boxShadow: AionShadows.dialog(colors, isDark),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _leadingIcon(),
                          const SizedBox(height: AionSpacing.sp16),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: AionText.dialogTitle.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AionSpacing.sp8),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style: AionText.bodySm.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AionSpacing.sp24),
                          isNarrow ? _narrowActions() : _wideActions(),
                        ],
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
  }

  Widget _leadingIcon() {
    final iconColor = isDestructive ? colors.danger : colors.primary;
    final fillAlpha = isDark ? fillAlphaObsidian : fillAlphaArctic;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: fillAlpha),
        shape: BoxShape.circle,
      ),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: PhosphorIcon(
            isDestructive
                ? PhosphorIcons.trashLight
                : PhosphorIcons.warningCircleLight,
            size: 20,
            color: iconColor,
          ),
        ),
      ),
    );
  }

  Widget _cancelButton({bool isFullWidth = false}) {
    return AppButton(
      label: cancelLabel,
      variant: AppButtonVariant.secondary,
      isFullWidth: isFullWidth,
      onPressed: () => onResolve(false),
    );
  }

  Widget _confirmButton({bool isFullWidth = false}) {
    return AppButton(
      label: confirmLabel,
      variant: isDestructive
          ? AppButtonVariant.destructive
          : AppButtonVariant.primary,
      isFullWidth: isFullWidth,
      onPressed: () => onResolve(true),
    );
  }

  Widget _wideActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _cancelButton(),
        const SizedBox(width: AionSpacing.sp12),
        _confirmButton(),
      ],
    );
  }

  Widget _narrowActions() {
    // Destructive action gets thumb-priority (top) position on narrow
    // viewports, matching iOS/Android action-sheet convention.
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: _confirmButton(isFullWidth: true),
        ),
        const SizedBox(height: AionSpacing.sp8),
        SizedBox(
          width: double.infinity,
          child: _cancelButton(isFullWidth: true),
        ),
      ],
    );
  }
}
