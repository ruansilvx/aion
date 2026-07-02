import 'package:flutter/widgets.dart';

import 'package:aion/core/theme/aion_theme.dart';

class ThemeScope extends InheritedWidget {
  const ThemeScope({super.key, required this.theme, required super.child});

  final AionThemeData theme;

  static AionThemeData of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'ThemeScope not found in widget tree');
    return scope!.theme;
  }

  @override
  bool updateShouldNotify(ThemeScope oldWidget) => theme != oldWidget.theme;
}
