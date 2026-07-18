// presentation/widgets/empty_hub_state.dart — EmptyHubState first-run illustration + CTA (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';

/// Shown on the Hub when no projects exist yet (first run): a filled
/// faction-motif emblem, a short explanation, and a "New Project" call
/// to action. See
/// `aion-arch/changes/multi-project-hub/design.md` §3.
class EmptyHubState extends StatelessWidget {
  /// Creates an [EmptyHubState]. [onNewProject] is called when the CTA
  /// is activated.
  const EmptyHubState({super.key, required this.onNewProject});

  /// Called when the "New Project" call to action is activated.
  final VoidCallback onNewProject;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Emblem(colors: c, isDark: t.isDark),
            const SizedBox(height: 22),
            Text(
              context.l10n.projectHubEmptyTitle,
              textAlign: TextAlign.center,
              style: AionText.h2.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: AionSpacing.sp8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                context.l10n.projectHubEmptyBody,
                textAlign: TextAlign.center,
                style: AionText.body.copyWith(
                  color: c.textSecondary,
                  height: 1.55,
                ),
              ),
            ),
            const SizedBox(height: AionSpacing.sp24),
            _NewProjectCta(
              colors: c,
              isDark: t.isDark,
              onNewProject: onNewProject,
            ),
          ],
        ),
      ),
    );
  }
}

/// [EmptyHubState]'s filled faction-motif emblem illustration.
class _Emblem extends StatelessWidget {
  const _Emblem({required this.colors, required this.isDark});

  final AionColors colors;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.emblemGlow(isDark),
              borderRadius: BorderRadius.all(AionRadius.xl),
              boxShadow: [
                BoxShadow(
                  color: c.emblemGlow(isDark),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const SizedBox(width: 84, height: 84),
          ),
          DecoratedBox(
            decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
            child: const SizedBox(width: 80, height: 80),
          ),
          const PhosphorIcon(
            PhosphorIcons.plusLight,
            size: 36,
            color: Color(0xFFFFFFFF),
          ),
        ],
      ),
    );
  }
}

/// [EmptyHubState]'s "New Project" call-to-action button.
class _NewProjectCta extends StatelessWidget {
  const _NewProjectCta({
    required this.colors,
    required this.isDark,
    required this.onNewProject,
  });

  final AionColors colors;
  final bool isDark;
  final VoidCallback onNewProject;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return GestureDetector(
      onTap: onNewProject,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.primary,
          borderRadius: BorderRadius.all(AionRadius.lg),
          boxShadow: AionShadows.fab(c, isDark),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PhosphorIcon(
                PhosphorIcons.plusLight,
                size: 17,
                color: Color(0xFFFFFFFF),
              ),
              const SizedBox(width: AionSpacing.sp8),
              Text(
                context.l10n.projectHubNewProjectAction,
                style: AionText.button.copyWith(color: const Color(0xFFFFFFFF)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
