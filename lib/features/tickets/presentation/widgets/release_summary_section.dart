// presentation/widgets/release_summary_section.dart — ReleaseSummarySection widget (presentation layer).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/linked_ticket_ref.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';

/// The Release section a `release`-type ticket's detail screen renders — the
/// type gets no Documentation-mode content of its own otherwise (see
/// `aion-arch/specs/tickets.md`'s "Documentation-mode sections", which
/// excludes `release`). Lists [linkedWork] via the existing `design_system`
/// [LinkedTicketsSection] molecule, reused as-is per `AIO-1782` §5.1 — this
/// widget contributes only the eyebrow above it and the Prepare Release
/// trigger below it. Feature-level composition, not a `design_system/`
/// promotion, since it's tied to `release`-ticket business logic (the Prepare
/// Release trigger itself). Added for `AIO-1782`.
class ReleaseSummarySection extends StatelessWidget {
  /// Creates a [ReleaseSummarySection].
  const ReleaseSummarySection({
    super.key,
    required this.linkedWork,
    required this.preparing,
    required this.onPrepare,
    required this.onTapLinked,
    required this.onRemoveLinked,
  });

  /// The `epic`/`story`/`task`/`bug` tickets `relatesTo`-linked to this
  /// release, as loaded by `TicketsCubit.loadDocumentRelations`. May be
  /// empty — see [_EmptyLinkedWorkNotice].
  final List<LinkedTicketRef> linkedWork;

  /// Whether `TicketsCubit.prepareReleaseDraft` is currently running for
  /// this release ticket.
  final bool preparing;

  /// Called when the Prepare Release action is activated. Disabled
  /// (never called) while [preparing] is `true` or [linkedWork] is empty.
  final VoidCallback onPrepare;

  /// Called with a linked ticket's id when its row is tapped.
  final ValueChanged<String> onTapLinked;

  /// Called with a link row's underlying link id once its removal is
  /// confirmed.
  final ValueChanged<String> onRemoveLinked;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 15, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.releaseSummarySectionEyebrow,
              style: AionText.caption.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: 14),
            if (linkedWork.isEmpty)
              const _EmptyLinkedWorkNotice()
            else
              LinkedTicketsSection(
                links: linkedWork,
                // A release's scope is a containment relation, not a
                // switchable one — a single-option set disables
                // `LinkedTicketsSection`'s own inline retype affordance
                // (see that widget's `_editable` getter).
                linkTypeOptions: const [TicketLinkType.relatesTo],
                onTap: onTapLinked,
                onRemove: onRemoveLinked,
                onChangeType: (_, _) {},
              ),
            const SizedBox(height: AionSpacing.sp16),
            _PrepareReleaseButton(
              preparing: preparing,
              disabledByEmptyScope: !preparing && linkedWork.isEmpty,
              onPressed: (preparing || linkedWork.isEmpty) ? null : onPrepare,
            ),
          ],
        ),
      ),
    );
  }
}

/// The Prepare Release trigger, wrapping [AppButton] with a hover-dwell
/// tooltip for its disabled-by-empty-scope state (design.md §1.3.6):
/// `"Link the work this release ships first"`, appearing after a 450ms hover
/// dwell with a 120ms fade-in, dismissing instantly on exit. Mirrors
/// `AgentCostHint`'s existing bare `OverlayEntry` +
/// `CompositedTransformFollower` + dwell-`Timer` pattern
/// (`aion/lib/features/providers/presentation/widgets/agent_cost_hint.dart`)
/// rather than a new one. The always-visible empty-state notice (§1.4) already
/// states the same reason for a non-hovering/keyboard user — this tooltip is a
/// hover-only supplement, not the only place the reason is surfaced. Added for
/// `AIO-1782`'s `/verify` round-1 fix-up, T19.
class _PrepareReleaseButton extends StatefulWidget {
  const _PrepareReleaseButton({
    required this.preparing,
    required this.disabledByEmptyScope,
    required this.onPressed,
  });

  /// Whether `prepareReleaseDraft` is in flight — drives the button's
  /// loading label/icon; the tooltip never shows in this state.
  final bool preparing;

  /// Whether the button is disabled specifically because there's nothing
  /// linked — the condition the hover tooltip explains.
  final bool disabledByEmptyScope;

  final VoidCallback? onPressed;

  @override
  State<_PrepareReleaseButton> createState() => _PrepareReleaseButtonState();
}

class _PrepareReleaseButtonState extends State<_PrepareReleaseButton> {
  final _link = LayerLink();
  final ValueNotifier<bool> _visible = ValueNotifier(false);
  OverlayEntry? _entry;
  Timer? _hoverOpenTimer;

  void _insertIfNeeded() {
    if (_entry != null) {
      _visible.value = true;
      return;
    }
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _visible.value = false;
    final entry = OverlayEntry(
      builder: (_) => _DisabledPrepareTooltip(link: _link, visible: _visible),
    );
    _entry = entry;
    overlay.insert(entry);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _visible.value = true;
    });
  }

  void _openAfterDwell() {
    if (!widget.disabledByEmptyScope) return;
    _hoverOpenTimer?.cancel();
    _hoverOpenTimer = Timer(const Duration(milliseconds: 450), _insertIfNeeded);
  }

  /// Dismisses instantly on exit, per design.md §1.3.6.
  void _close() {
    _hoverOpenTimer?.cancel();
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _hoverOpenTimer?.cancel();
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) => _openAfterDwell(),
        onExit: (_) => _close(),
        child: AppButton(
          label: widget.preparing
              ? context.l10n.releaseSummaryPreparingLabel
              : context.l10n.releaseSummaryPrepareButton,
          icon: widget.preparing ? null : PhosphorIcons.tagLight,
          isFullWidth: true,
          onPressed: widget.onPressed,
        ),
      ),
    );
  }
}

/// The tooltip panel [_PrepareReleaseButtonState._insertIfNeeded] inserts
/// into the root [Overlay] — anchored above the button, per design.md
/// §1.3.6.
class _DisabledPrepareTooltip extends StatelessWidget {
  const _DisabledPrepareTooltip({required this.link, required this.visible});

  final LayerLink link;
  final ValueNotifier<bool> visible;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    // See `AgentCostHint`'s own tooltip for why `left: 0, top: 0` here is
    // load-bearing, not decorative — it satisfies `Overlay`'s internal
    // `_Theatre` positioning requirement without affecting the actual
    // screen placement, which `CompositedTransformFollower` owns below.
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topCenter,
        followerAnchor: Alignment.bottomCenter,
        offset: const Offset(0, -8),
        child: ExcludeSemantics(
          child: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, isVisible, _) => AnimatedOpacity(
              opacity: isVisible ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border.all(color: c.borderStrong, width: 1),
                      borderRadius: BorderRadius.all(AionRadius.sm),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF000000,
                          ).withValues(alpha: t.isDark ? 0.55 : 0.16),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      child: Text(
                        context.l10n.releaseSummaryPrepareDisabledTooltip,
                        style: AionText.bodySm.copyWith(color: c.textPrimary),
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

/// The section's empty-scope state — replaces [LinkedTicketsSection]
/// entirely when [ReleaseSummarySection.linkedWork] is empty, naming the
/// release-specific consequence (rather than that molecule's own generic
/// "no links" line). The Prepare Release button stays rendered below it
/// in its disabled state regardless — never hidden, so the path stays
/// discoverable. Per design.md §1.4.
class _EmptyLinkedWorkNotice extends StatelessWidget {
  const _EmptyLinkedWorkNotice();

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.noticeFill(t.isDark),
        border: Border.all(color: c.noticeBorder(t.isDark), width: 1),
        borderRadius: BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PhosphorIcon(
              PhosphorIcons.linkSimpleBreakLight,
              size: 15,
              color: c.textMuted,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                context.l10n.releaseSummaryEmptyMessage,
                style: AionText.bodySm.copyWith(color: c.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
