// core/widgets/app_header.dart — AppHeader primitive widget (core layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/theme/aion_radius.dart';
import 'package:aion/core/theme/aion_text.dart';
import 'package:aion/core/theme/theme_scope.dart';

/// Aion's screen-header primitive — back button + title + optional trailing
/// widget. Replaces `AppBar`/`Scaffold` chrome; used by the create and
/// detail screens. The list screen composes its own header layout instead.
class AppHeader extends StatelessWidget {
  /// Creates an [AppHeader].
  const AppHeader({
    super.key,
    required this.title,
    this.showBack = false,
    this.onBack,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 6, 20, 14),
  });

  /// The header title text.
  final String title;

  /// Whether to render the back button.
  final bool showBack;

  /// Called when the back button is tapped. Ignored if [showBack] is false.
  final VoidCallback? onBack;

  /// Optional widget rendered at the trailing edge (e.g. an avatar or a
  /// more-actions icon).
  final Widget? trailing;

  /// Outer padding. Callers pass screen-specific values (see design.md §3).
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return ColoredBox(
      color: c.surface,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (showBack) ...[
              Semantics(
                label: 'Back',
                button: true,
                child: GestureDetector(
                  onTap: onBack,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.surfaceHover,
                      border: Border.all(color: c.border, width: 1),
                      borderRadius: BorderRadius.all(AionRadius.iconBtn),
                    ),
                    child: SizedBox(
                      width: 37,
                      height: 37,
                      child: Center(
                        child: PhosphorIcon(
                          PhosphorIcons.caretLeftLight,
                          size: 18,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AionSpacing.sp12),
            ],
            Expanded(
              child: Text(
                title,
                style: AionText.h2.copyWith(color: c.textPrimary),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
