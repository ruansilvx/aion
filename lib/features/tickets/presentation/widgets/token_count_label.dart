// presentation/widgets/token_count_label.dart — TokenCountLabel widget + formatTokenCount formatter (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/design_system/tokens/aion_colors.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';

/// Formats [tokens] as a compact `"~12.3K"`/`"~1.2M"`-style bare number, or
/// the exact integer below 1000 — the one shared formatter every token count
/// display in the app uses, so `TicketBoardCard`, `TicketMetadataSection`, and
/// `_CodingExecutionSection` always agree on how a given count reads. Negative
/// input is clamped to `0` (defensive — a token count is never meaningfully
/// negative). One decimal place, with a trailing `".0"` dropped (`12000` →
/// `"12K"`, not `"12.0K"`). Returns only the bare number — the `~`
/// approximation prefix and the `"tokens"` unit word are composed by
/// [TokenCountLabel] itself, not by this formatter, so the same output can
/// compose into `"~12.3K"`, `"~12K–34K tokens"`, or `"842 tokens"` depending
/// on call site. See `AIO-2455` §0.2.
String formatTokenCount(int tokens) {
  final n = tokens < 0 ? 0 : tokens;
  if (n < 1000) return '$n';

  String abbrev(double value) {
    final s = value.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  if (n < 1000000) return '${abbrev(n / 1000.0)}K';
  return '${abbrev(n / 1000000.0)}M';
}

/// Which figure a [TokenCountLabel] renders — a pre-flight forecast ([range])
/// or a real accumulated total ([total]). See `AIO-2455` §5.2.
enum TokenCountMode {
  /// A pre-flight predicted `"~{lo}–{hi} tokens"` range.
  range,

  /// A running/actual accumulated `"~{v} tokens"` total.
  total,
}

/// Which visual size a [TokenCountLabel] renders at — [compact] for the board
/// meta-chip row (no unit word), [detail] for the two detail-screen placements
/// (adds the `"tokens"` unit word). See `AIO-2455` §5.2.
enum TokenCountVariant {
  /// Board meta-chip row sizing — `gauge` 11, mono 10.5 value, no unit
  /// word. Geometry is byte-identical to `RollupBadge`.
  compact,

  /// Detail-screen sizing — `gauge` 12, mono 11 value, trailing muted
  /// `" tokens"` unit word.
  detail,
}

/// A small, quiet, caption-weight, non-interactive label rendering either a
/// predicted token-count **range** ([TokenCountMode.range], via
/// [TokenCountLabel.range]) or a running/actual **total**
/// ([TokenCountMode.total], via [TokenCountLabel.total]) — the one shared
/// widget behind all three token-cost-prediction display surfaces:
/// `TicketBoardCard`'s meta-chip row, `TicketMetadataSection`'s predicted-
/// range line, and `_CodingExecutionSection`'s running-total line.
/// Deliberately **not** an `AiSuggestionBadge` reuse — a token count is a
/// measured/derived number, not an AI-authored field value, so it carries
/// no `sparkle` iconography and no `primary`/`primarySubtle` AI framing.
/// It reads as neutral metrics chrome, in the same visual family as
/// `RollupBadge` (`neutralTint` fill, `AionRadius.sm`), whose compact
/// geometry this widget's [TokenCountVariant.compact] matches exactly.
///
/// Non-interactive: no `onTap`, no cursor change, no focus node, and a single
/// resting visual state in both variants and both modes — no
/// hover/focus/pressed/disabled/error state of its own. See `AIO-2455` §1
/// (Component Spec §1) for the full visual spec this class implements.
class TokenCountLabel extends StatelessWidget {
  /// Creates a [TokenCountLabel] rendering [low]–[high] as a predicted
  /// range (`"~{lo}–{hi}"`, plus a `" tokens"` unit word at
  /// [TokenCountVariant.detail]). Prefer [TokenCountLabel.total] instead
  /// when `low == high` — a degenerate one-value range reads better as a
  /// settled total (Component Spec §1.1).
  const TokenCountLabel.range({
    super.key,
    required this.low,
    required this.high,
    required this.variant,
    this.onSelectedRow = false,
  }) : mode = TokenCountMode.range,
       total = null,
       live = false;

  /// Creates a [TokenCountLabel] rendering [total] as a running/actual
  /// total (`"~{v} tokens"` once abbreviated, or the bare exact integer
  /// below 1000 with no `~`). [live] is accepted purely for call-site
  /// documentation/semantic pairing with a sibling liveness dot the
  /// caller renders alongside this label (see
  /// `_CodingExecutionSection`'s in-flight treatment, Component Spec
  /// §4.3) — it has **no visual effect on this widget itself**: the
  /// label renders identically whether [live] is `true` or `false`
  /// ("the standard pill, unchanged — no accent recoloring", Component
  /// Spec §4.3).
  const TokenCountLabel.total({
    super.key,
    required this.total,
    required this.variant,
    this.live = false,
    this.onSelectedRow = false,
  }) : mode = TokenCountMode.total,
       low = null,
       high = null;

  /// Which figure this label renders — set by which named constructor was
  /// used.
  final TokenCountMode mode;

  /// Which visual sizing this label renders at.
  final TokenCountVariant variant;

  /// Range mode's lower bound. `null` outside [TokenCountMode.range].
  final int? low;

  /// Range mode's upper bound. `null` outside [TokenCountMode.range].
  final int? high;

  /// Total mode's accumulated count. `null` outside [TokenCountMode.total].
  final int? total;

  /// See [TokenCountLabel.total]'s dartdoc — accepted for call-site
  /// semantic pairing only, has no effect on this widget's own rendering.
  final bool live;

  /// Whether the row/card this label sits on is currently selected —
  /// switches the fill/border treatment the same way `RollupBadge.onSelectedRow`
  /// does (Component Spec §1.6): a solid `surface` fill with a 1px
  /// `neutralBorderTint` hairline instead of the default translucent
  /// `neutralTint` fill, since the translucent tint would muddy against
  /// `primarySubtle`. `TicketBoardCard` has no selection background, so
  /// board usage never passes `true`.
  final bool onSelectedRow;

  /// Composes the bare value string (no unit word) — `"~{lo}–{hi}"` for
  /// [TokenCountMode.range] (always `~`-prefixed, en dash `–` U+2013, no
  /// surrounding spaces — a forecast is inherently approximate), or
  /// `"~{v}"`/`"{v}"` for [TokenCountMode.total] (`~`-prefixed only once
  /// [formatTokenCount] has abbreviated the value; the exact integer
  /// below 1000 carries no `~`). See Component Spec §1.1.
  String _composeValue() {
    switch (mode) {
      case TokenCountMode.range:
        return '~${formatTokenCount(low!)}–${formatTokenCount(high!)}';
      case TokenCountMode.total:
        final value = total!;
        final formatted = formatTokenCount(value);
        return value < 1000 ? formatted : '~$formatted';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final compact = variant == TokenCountVariant.compact;

    final valueStyle = AionText.key.copyWith(
      fontSize: compact ? 10.5 : 11,
      color: c.textSecondary,
    );
    final unitStyle = AionText.key.copyWith(
      fontWeight: FontWeight.w400,
      color: c.textMuted,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: onSelectedRow ? c.surface : c.neutralTint(t.isDark),
        borderRadius: const BorderRadius.all(AionRadius.sm),
        border: onSelectedRow
            ? Border.all(color: c.neutralBorderTint(t.isDark), width: 1)
            : null,
      ),
      child: Padding(
        padding: compact
            ? const EdgeInsets.fromLTRB(6, 2, 7, 2)
            : const EdgeInsets.fromLTRB(7, 3, 9, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            PhosphorIcon(
              PhosphorIcons.gauge,
              size: compact ? 11 : 12,
              color: c.textSecondary,
            ),
            SizedBox(width: compact ? 5 : 6),
            Text.rich(
              TextSpan(
                text: _composeValue(),
                style: valueStyle,
                children: compact
                    ? null
                    : [TextSpan(text: ' tokens', style: unitStyle)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
