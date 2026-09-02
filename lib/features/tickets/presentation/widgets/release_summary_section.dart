// presentation/widgets/release_summary_section.dart — ReleaseSummarySection widget (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/linked_ticket_ref.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';

/// The Release section a `release`-type ticket's detail screen renders —
/// the type gets no Documentation-mode content of its own otherwise (see
/// `aion-arch/specs/tickets.md`'s "Documentation-mode sections", which
/// excludes `release`). Lists [linkedWork] via the existing
/// `design_system` [LinkedTicketsSection] molecule, reused as-is per
/// `aion-arch/changes/release-preparation-and-tagging/design.md` §5.1 —
/// this widget contributes only the eyebrow above it and the Prepare
/// Release trigger below it. Feature-level composition, not a
/// `design_system/` promotion, since it's tied to `release`-ticket
/// business logic (the Prepare Release trigger itself). Added for
/// `aion-arch/changes/release-preparation-and-tagging`.
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
            AppButton(
              label: preparing
                  ? context.l10n.releaseSummaryPreparingLabel
                  : context.l10n.releaseSummaryPrepareButton,
              icon: preparing ? null : PhosphorIcons.tagLight,
              isFullWidth: true,
              onPressed: (preparing || linkedWork.isEmpty)
                  ? null
                  : onPrepare,
            ),
          ],
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
