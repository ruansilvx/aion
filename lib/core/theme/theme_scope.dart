// core/theme/theme_scope.dart — ThemeScope InheritedWidget (core/theme layer).

import 'package:flutter/widgets.dart';

import 'package:aion/core/theme/aion_theme.dart';

/// Provides the active [AionThemeData] to the widget tree. This is Aion's
/// sole theming mechanism — use `ThemeScope.of(context)`, never
/// `Theme.of(context)`. Wraps the root `WidgetsApp.router`.
class ThemeScope extends InheritedWidget {
  /// Creates a [ThemeScope] exposing [theme] to descendants.
  const ThemeScope({super.key, required this.theme, required super.child});

  /// The theme currently in effect.
  final AionThemeData theme;

  /// Returns the nearest ancestor [ThemeScope]'s theme. Asserts if none is
  /// found — every screen must be a descendant of the root [ThemeScope].
  static AionThemeData of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'ThemeScope not found in widget tree');
    return scope!.theme;
  }

  @override
  bool updateShouldNotify(ThemeScope oldWidget) => theme != oldWidget.theme;
}
