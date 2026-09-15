// core/utils/mouse_drag_scroll_behavior.dart — App-wide ScrollBehavior widening dragDevices to include mouse (core layer).

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';

/// The base (non-Material) [ScrollBehavior]'s [dragDevices] deliberately
/// excludes [PointerDeviceKind.mouse] — Flutter's own default assumes a
/// touch/stylus/trackpad input model. On desktop (Aion's actual target
/// platform, per project.md), that leaves every scrollable that depends on
/// click-and-drag rather than mouse-wheel input unreachable with a plain
/// mouse: a vertical wheel scroll over a horizontal-only scrollable (a
/// `MarkdownView` fenced code block or table, `_buildCodeBlock`/
/// `_buildTable`) bubbles up to whichever vertical scrollable contains it
/// instead of moving the horizontal one, and a manual click-drag gesture
/// over it does nothing at all — confirmed live (`AIO-2905`): neither
/// input reached a real chat transcript's code block with an unbroken line
/// past the visible width.
///
/// Passed once to the app's root `WidgetsApp.router` (see `main.dart`) —
/// one central override fixes every scrollable in the app at once, not
/// just the two `MarkdownView` cases above.
class MouseDragScrollBehavior extends ScrollBehavior {
  /// Creates a [MouseDragScrollBehavior].
  const MouseDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}
