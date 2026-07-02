import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/theme/aion_radius.dart';
import 'package:aion/core/theme/aion_text.dart';
import 'package:aion/core/theme/theme_scope.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.showBack = false,
    this.onBack,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 6, 20, 14),
  });

  final String title;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;
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
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
