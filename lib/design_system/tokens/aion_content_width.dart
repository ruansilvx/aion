// design_system/tokens/aion_content_width.dart — Content max-width
// token pair (design-system layer).

/// Aion's content max-width scale. Every screen that constrains its
/// content column to a readable/scannable width uses one of these two
/// values via [ContentMaxWidth] — never a raw number in widget code.
abstract final class AionContentWidth {
  /// Forms and short interactive flows (create/edit screens). Matches
  /// the value `NewProjectScreen` established before this widget
  /// existed.
  static const double form = 520;

  /// Reading-oriented content: ticket detail, page detail/documentation
  /// content, documentation tree/search list, ticket list.
  static const double reading = 840;
}
