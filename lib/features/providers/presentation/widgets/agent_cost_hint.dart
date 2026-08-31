// presentation/widgets/agent_cost_hint.dart — AgentCostHint info-tooltip trigger (presentation layer).

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
/// apply to a node that will never actually be evaluated. Added for
/// `aion-arch/changes/decision-graph-agentjudgment-condition`; see that
/// change's design.md §5.
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
  OverlayEntry? _entry;
  bool _hovered = false;

  void _show() {
    if (_entry != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _AgentCostHintTooltip(
        link: _link,
        showLatencyLine: widget.showLatencyLine,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final isDark = ThemeScope.of(context).isDark;
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        cursor: SystemMouseCursors.help,
        onEnter: (_) {
          setState(() => _hovered = true);
          _show();
        },
        onExit: (_) {
          setState(() => _hovered = false);
          _hide();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _entry == null ? _show() : _hide(),
          child: Semantics(
            label: context.l10n.decisionGraphAgentCostHintSemantics,
            button: true,
            child: SizedBox(
              width: 24,
              height: 24,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _hovered
                          ? c.textSecondary.withValues(alpha: 0.45)
                          : c.neutralBorderTint(isDark),
                      width: 1.2,
                    ),
                  ),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: Center(
                      child: Text(
                        'i',
                        style: AionText.caption.copyWith(
                          color: _hovered ? c.textSecondary : c.textMuted,
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
    );
  }
}

/// The tooltip panel [_AgentCostHintState._show] inserts into the root
/// [Overlay] — opaque `surface` fill, positioned above and right-aligned
/// to the trigger via [CompositedTransformFollower]. Per design.md §5.3.
class _AgentCostHintTooltip extends StatelessWidget {
  const _AgentCostHintTooltip({
    required this.link,
    required this.showLatencyLine,
  });

  final LayerLink link;
  final bool showLatencyLine;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    return CompositedTransformFollower(
      link: link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.topRight,
      followerAnchor: Alignment.bottomRight,
      offset: const Offset(0, -8),
      child: ExcludeSemantics(
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                      style: AionText.time.copyWith(color: c.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
