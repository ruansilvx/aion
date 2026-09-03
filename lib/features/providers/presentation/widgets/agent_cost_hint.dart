// presentation/widgets/agent_cost_hint.dart — AgentCostHint info-tooltip trigger (presentation layer).

import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';

/// The small "i" info-trigger shown next to an `ASK ·` eyebrow/badge
/// (canvas node card and outline row) that surfaces the `agentJudgment`
/// condition's round-trip cost on hover/tap — "this node calls the agent
/// mid-turn and costs a few seconds," a fact the `ASK ·` accent itself
/// signals but doesn't quantify. Built from a bare [OverlayEntry] +
/// [CompositedTransformTarget]/[CompositedTransformFollower], never
/// Material's `Tooltip` — per this project's Material-widget constraint.
/// Never surfaced on an error/incomplete outline row (see
/// `DecisionOutlineList`'s own call site) — the cost statement doesn't
/// apply to a node that will never actually be evaluated.
///
/// Per design.md §5.2: hover fills a `neutralTint` circle behind the glyph and
/// opens the tooltip after a 120ms delay; keyboard focus re-tones the
/// glyph/ring to `primary` and opens the tooltip immediately; a tap/touch
/// toggles a sticky `primaryWash`-filled open state that persists until the
/// next tap anywhere (via [TapRegion]). Added for `AIO-613`; see its linked
/// Documentation page, §5.
class AgentCostHint extends StatefulWidget {
  /// Creates an [AgentCostHint]. [showLatencyLine] adds the canvas card's
  /// second, `~2–6s per evaluation` line (design.md §5.3) — omitted on the
  /// outline row's more compact mount.
  const AgentCostHint({super.key, this.showLatencyLine = false});

  /// Whether to render the optional second tooltip line.
  final bool showLatencyLine;

  @override
  State<AgentCostHint> createState() => _AgentCostHintState();
}

class _AgentCostHintState extends State<AgentCostHint> {
  final _link = LayerLink();
  final ValueNotifier<bool> _visible = ValueNotifier(false);
  OverlayEntry? _entry;
  Timer? _hoverOpenTimer;
  bool _hovered = false;
  bool _focused = false;
  bool _pressedOpen = false;

  /// Inserts the tooltip overlay if it isn't already there, then kicks
  /// its fade/slide-in (§5.3's 120ms entry) on the next frame — the
  /// overlay's first build must paint at opacity 0 before animating to 1,
  /// otherwise there's nothing to animate from.
  void _insertIfNeeded() {
    if (_entry != null) {
      _visible.value = true;
      return;
    }
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _visible.value = false;
    final entry = OverlayEntry(
      builder: (_) => _AgentCostHintTooltip(
        link: _link,
        showLatencyLine: widget.showLatencyLine,
        visible: _visible,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _visible.value = true;
    });
  }

  /// Opens immediately — keyboard focus (§5.2's "Tooltip opens
  /// immediately") and a tap/touch toggle both use this.
  void _openNow() {
    _hoverOpenTimer?.cancel();
    _insertIfNeeded();
  }

  /// Opens after §5.2's 120ms hover delay.
  void _openAfterHoverDelay() {
    _hoverOpenTimer?.cancel();
    _hoverOpenTimer = Timer(const Duration(milliseconds: 120), _insertIfNeeded);
  }

  /// Fades the tooltip out (§5.3's 80ms exit) before actually removing
  /// the overlay entry.
  void _close() {
    _hoverOpenTimer?.cancel();
    if (_entry == null) return;
    _visible.value = false;
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      _entry?.remove();
      _entry = null;
    });
  }

  /// Closes only if nothing else is still holding the tooltip open —
  /// hover, keyboard focus, and the sticky tap-toggle are independent
  /// reasons to keep it visible.
  void _closeIfNothingElseHolding() {
    if (!_hovered && !_focused && !_pressedOpen) _close();
  }

  @override
  void dispose() {
    _hoverOpenTimer?.cancel();
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _handleTap() {
    setState(() => _pressedOpen = !_pressedOpen);
    if (_pressedOpen) {
      _openNow();
    } else {
      _closeIfNothingElseHolding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final active = _hovered || _focused || _pressedOpen;
    final iconColor = _focused
        ? c.primary
        : active
        ? c.textSecondary
        : c.textMuted;
    final ringColor = _focused
        ? c.primary
        : _hovered
        ? c.textSecondary.withValues(alpha: 0.45)
        : c.neutralBorderTint(t.isDark);
    final Color? fill = _pressedOpen
        ? c.primaryWash(t.isDark)
        : _hovered
        ? c.neutralTint(t.isDark)
        : null;
    // §5.1's 24×24 hit target grows to ≥44×44 on touch platforms — this
    // widget mounts on both the canvas card and the outline row, so
    // (unlike §5.1's literal "on the canvas card only") it applies the
    // larger target on both rather than threading a host flag through
    // for a touch-target nuance neither host otherwise cares about.
    final isTouchPlatform =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    final hitTargetSize = isTouchPlatform ? 44.0 : 24.0;

    return TapRegion(
      onTapOutside: (_) {
        if (!_pressedOpen) return;
        setState(() => _pressedOpen = false);
        _closeIfNothingElseHolding();
      },
      child: CompositedTransformTarget(
        link: _link,
        // MouseRegion wraps FocusableActionDetector (not the reverse) —
        // matches `OverlayMenuItem`'s established nesting for the same
        // plain-hover-vs-focus-ring split.
        child: MouseRegion(
          cursor: SystemMouseCursors.help,
          onEnter: (_) {
            setState(() => _hovered = true);
            _openAfterHoverDelay();
          },
          onExit: (_) {
            setState(() => _hovered = false);
            _closeIfNothingElseHolding();
          },
          child: FocusableActionDetector(
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _handleTap();
                  return null;
                },
              ),
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) {
                  if (_pressedOpen) setState(() => _pressedOpen = false);
                  _closeIfNothingElseHolding();
                  return null;
                },
              ),
            },
            onShowFocusHighlight: (focused) {
              setState(() => _focused = focused);
              if (focused) {
                _openNow();
              } else {
                _closeIfNothingElseHolding();
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleTap,
              child: Semantics(
                label: context.l10n.decisionGraphAgentCostHintSemantics,
                button: true,
                child: SizedBox(
                  width: hitTargetSize,
                  height: hitTargetSize,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      curve: Curves.easeOut,
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: fill,
                        border: Border.all(color: ringColor, width: 1.2),
                        boxShadow: _focused
                            ? [BoxShadow(color: c.primary, spreadRadius: 1.5)]
                            : null,
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: Center(
                            child: Text(
                              'i',
                              style: AionText.caption.copyWith(
                                color: iconColor,
                                fontWeight: FontWeight.w700,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tooltip panel [_AgentCostHintState._insertIfNeeded] inserts into
/// the root [Overlay] — opaque `surface` fill, positioned above and
/// right-aligned to the trigger via [CompositedTransformFollower]. Per
/// design.md §5.3, including the 120ms fade/slide-in and 80ms fade-out
/// [visible] drives (`AnimatedOpacity`/`AnimatedSlide`, `Curves.easeOut`
/// in and `Curves.easeIn` out — the same asymmetric-curve convention as
/// this widget's own hover-fill transition).
class _AgentCostHintTooltip extends StatelessWidget {
  const _AgentCostHintTooltip({
    required this.link,
    required this.showLatencyLine,
    required this.visible,
  });

  final LayerLink link;
  final bool showLatencyLine;
  final ValueNotifier<bool> visible;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    // `left`/`top` here are load-bearing, not decorative — and can't be
    // omitted. `Overlay`'s internal `_Theatre` (a `Stack`) only shrink-wraps a
    // child's own intrinsic size when `StackParentData.isPositioned` is true,
    // which requires at least one of left/top/right/bottom/width/ height to be
    // non-null; a bare `Positioned()` with none of them set is *not*
    // positioned at all and is silently treated exactly like an unwrapped
    // child — stretched to the theatre's full size. `left: 0, top: 0`
    // satisfies `isPositioned` while leaving the actual screen placement
    // entirely to [CompositedTransformFollower]'s paint-time transform below,
    // which is unaffected by this widget's layout position. Confirmed
    // empirically (a debug-colored child filled the entire app window instead
    // of its requested 240×~50, and remained stretched even after a first
    // attempt with a geometry-less `Positioned`) while fixing `AIO-613`'s
    // `/verify` findings — pre-existing since that change's original `/apply`,
    // not introduced by this pass.
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topRight,
        followerAnchor: Alignment.bottomRight,
        offset: const Offset(0, -8),
        child: ExcludeSemantics(
          child: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, isVisible, _) => AnimatedSlide(
              offset: isVisible ? Offset.zero : const Offset(0, 0.06),
              duration: Duration(milliseconds: isVisible ? 120 : 80),
              curve: isVisible ? Curves.easeOut : Curves.easeIn,
              child: AnimatedOpacity(
                opacity: isVisible ? 1 : 0,
                duration: Duration(milliseconds: isVisible ? 120 : 80),
                curve: isVisible ? Curves.easeOut : Curves.easeIn,
                child: SizedBox(
                  width: 240,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border.all(color: c.borderStrong, width: 1),
                      borderRadius: BorderRadius.all(AionRadius.md),
                      boxShadow: AionShadows.card(c, t.isDark),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.decisionGraphAgentCostHintTooltip,
                            style: AionText.bodySm.copyWith(
                              color: c.textSecondary,
                              height: 1.4,
                            ),
                          ),
                          if (showLatencyLine) ...[
                            const SizedBox(height: 4),
                            Text(
                              context.l10n.decisionGraphAgentCostHintLatency,
                              style: AionText.time.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
