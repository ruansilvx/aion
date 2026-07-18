// presentation/widgets/project_switcher_menu.dart — ProjectSwitcherMenu workspace-sidebar entry point (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';

/// A small entry point living in the workspace's sidebar/nav that reads
/// "Switch Project" and returns the user to the Hub. Tapping it does
/// **not** open an inline list — project selection happens on the Hub
/// itself. See
/// `aion-arch/changes/multi-project-hub/design.md` §5.
class ProjectSwitcherMenu extends StatefulWidget {
  /// Creates a [ProjectSwitcherMenu]. [onSwitchProject] is called when
  /// activated.
  const ProjectSwitcherMenu({super.key, required this.onSwitchProject});

  /// Called when the row is tapped or activated via keyboard.
  final VoidCallback onSwitchProject;

  @override
  State<ProjectSwitcherMenu> createState() => _ProjectSwitcherMenuState();
}

class _ProjectSwitcherMenuState extends State<ProjectSwitcherMenu> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isEmphasized = _isHovered || _isPressed;

    final fill = isEmphasized ? c.surfaceHover : const Color(0x00000000);
    final foreground = isEmphasized ? c.textPrimary : c.textSecondary;
    final glyphColor = isEmphasized ? c.textSecondary : c.textSecondary;

    return Semantics(
      button: true,
      label: context.l10n.projectSwitcherMenuLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: FocusableActionDetector(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onSwitchProject();
                return null;
              },
            ),
          },
          onShowFocusHighlight: (value) => setState(() => _isFocused = value),
          child: GestureDetector(
            onTap: widget.onSwitchProject,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.all(AionRadius.md),
                boxShadow: _isFocused
                    ? AionShadows.focus(c, t.isDark)
                    : const [],
              ),
              child: Row(
                children: [
                  PhosphorIcon(
                    PhosphorIcons.hexagonLight,
                    size: 18,
                    color: glyphColor,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      context.l10n.projectSwitcherMenuLabel,
                      style: AionText.cardTitle.copyWith(
                        fontSize: 13.5,
                        color: foreground,
                      ),
                    ),
                  ),
                  PhosphorIcon(
                    PhosphorIcons.caretRightLight,
                    size: 15,
                    color: c.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
