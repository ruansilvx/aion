// design_system/atoms/content_max_width.dart — Max-width, centered
// content wrapper (design-system layer).

import 'package:flutter/widgets.dart';

import 'package:aion/design_system/tokens/aion_content_width.dart';

/// Which [AionContentWidth] value a [ContentMaxWidth] wrapper applies.
enum ContentWidthVariant {
  /// Forms and short interactive flows — [AionContentWidth.form].
  form,

  /// Reading-oriented content — [AionContentWidth.reading].
  reading,
}

/// Constrains [child] to a maximum width and centers it horizontally,
/// so content on wide viewports stays readable instead of stretching
/// edge-to-edge. Does not add its own horizontal padding — callers keep
/// their existing outer padding (e.g. [AionSpacing.sp20]) so narrow/
/// mobile viewports still get edge breathing room; this widget only
/// caps and centers once space exceeds the variant's max width.
class ContentMaxWidth extends StatelessWidget {
  /// Creates a [ContentMaxWidth] wrapping [child] at the given
  /// [variant]'s max width. Defaults to [ContentWidthVariant.reading],
  /// the more common case across in-scope screens.
  const ContentMaxWidth({
    super.key,
    required this.child,
    this.variant = ContentWidthVariant.reading,
  });

  /// The content to constrain and center.
  final Widget child;

  /// Which max-width value to apply.
  final ContentWidthVariant variant;

  @override
  Widget build(BuildContext context) {
    final maxWidth = switch (variant) {
      ContentWidthVariant.form => AionContentWidth.form,
      ContentWidthVariant.reading => AionContentWidth.reading,
    };
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
