// design_system/tokens/aion_text.dart — Typography token definitions (design-system layer).

import 'package:flutter/painting.dart';

/// Aion's typography scale. All styles are colorless — apply color at the
/// use site via `.copyWith(color: ...)` using an [AionColors] token, never
/// a raw [Color]. No `TextTheme` or `ThemeData` involvement.
abstract final class AionText {
  /// Manrope — UI and display text.
  static const _ui = 'Manrope';

  /// JetBrains Mono — keys, captions, and code-like text.
  static const _mono = 'JetBrainsMono';

  /// Largest display heading.
  static const display = TextStyle(
    fontFamily: _ui,
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.64,
    height: 1.1,
  );

  /// Page-level heading (e.g. the "Tickets" list-screen title).
  static const h1 = TextStyle(
    fontFamily: _ui,
    fontSize: 25,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.50,
    height: 1.15,
  );

  /// Screen-header heading (e.g. "New ticket", ticket detail title).
  static const h2 = TextStyle(
    fontFamily: _ui,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.22,
    height: 1.25,
  );

  /// Dialog headline text — confirmation/alert dialog titles. Sits between
  /// [h2] (22px, screen headers) and [cardTitle] (14px, row titles); a
  /// dialog needs headline weight without dominating a small centered card.
  static const dialogTitle = TextStyle(
    fontFamily: _ui,
    fontSize: 18,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.18,
    height: 1.3,
  );

  /// Primary body text, e.g. multiline description fields.
  static const body = TextStyle(
    fontFamily: _ui,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.5,
  );

  /// Smaller body text, e.g. hints and single-line field values.
  static const bodySm = TextStyle(
    fontFamily: _ui,
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.6,
  );

  /// Ticket-row and comment-header title text.
  static const cardTitle = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );

  /// Form field label text.
  static const label = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  /// Button label text.
  static const button = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w700,
  );

  /// Type-chip label text. Rendered as a pre-uppercased string, not a CSS
  /// text-transform.
  static const chip = TextStyle(
    fontFamily: _ui,
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.53,
  );

  /// Priority-badge label text for the detail-screen (larger) variant.
  static const priorityBig = TextStyle(
    fontFamily: _ui,
    fontSize: 10.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.53,
  );

  /// Priority-badge label text for the ticket-row (smaller) variant.
  static const prioritySm = TextStyle(
    fontFamily: _ui,
    fontSize: 8.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.43,
  );

  /// Monospace style for human-readable ticket IDs (e.g. "AIO-3").
  static const key = TextStyle(
    fontFamily: _mono,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.11,
  );

  /// Monospace, uppercase eyebrow/section-label style (e.g. "COMMENTS · 3").
  static const caption = TextStyle(
    fontFamily: _mono,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.54,
  );

  /// Monospace style for timestamps.
  static const time = TextStyle(
    fontFamily: _mono,
    fontSize: 11,
    fontWeight: FontWeight.w400,
  );

  /// Small proportional style for ancestor-breadcrumb subtitles under a
  /// parent-picker candidate row's title (e.g. "Auth Epic / OAuth
  /// redesign"). Deliberately not [caption] — caption's uppercase/wide
  /// tracking reads badly on a mixed-case ancestor path.
  static const breadcrumb = TextStyle(
    fontFamily: _ui,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.2,
  );

  /// `WorkspaceNavShell`'s compact (bottom-tab) nav-item label — smaller
  /// and non-uppercase, unlike [chip]. Deliberately not [chip]: chip's
  /// wide uppercase tracking reads badly under a small icon in a bottom
  /// tab bar.
  static const navTabLabel = TextStyle(
    fontFamily: _ui,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.06,
    height: 1.0,
  );
}
