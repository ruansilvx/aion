// core/widgets/app_toast.dart — AppToast primitive widget (core layer).

import 'package:flutter/widgets.dart';

import 'package:aion/core/theme/aion_radius.dart';
import 'package:aion/core/theme/aion_shadows.dart';
import 'package:aion/core/theme/aion_text.dart';
import 'package:aion/core/theme/theme_scope.dart';

/// Aion's transient-message primitive — replaces `SnackBar`/
/// `ScaffoldMessenger` with an [OverlayEntry] inserted directly into the
/// nearest [Overlay], so it works without a `Scaffold` ancestor.
abstract final class AppToast {
  /// Shows [message] in a toast pinned to the bottom of the screen for 3
  /// seconds, then removes it automatically.
  static void show(BuildContext context, String message) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          bottom: AionSpacing.sp24,
          left: AionSpacing.sp20,
          right: AionSpacing.sp20,
          child: Semantics(
            liveRegion: true,
            label: message,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.borderStrong, width: 1),
                borderRadius: BorderRadius.all(AionRadius.md),
                boxShadow: AionShadows.card(c, t.isDark),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AionSpacing.sp16,
                  vertical: AionSpacing.sp12,
                ),
                child: Text(
                  message,
                  style: AionText.bodySm.copyWith(color: c.textPrimary),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      entry.remove();
    });
  }
}
