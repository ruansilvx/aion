// design_system/molecules/gaps_and_open_questions_section.dart — GapsAndOpenQuestionsSection widget (design-system layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/molecules/type_chip.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';
import 'package:aion/features/tickets/domain/entities/gap_or_question_ref.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// A ticket-detail section listing every `knownGap`/`openQuestion` ticket
/// raised against the currently-viewed ticket, recursively rolled up from
/// its descendants — see [GapOrQuestionRef]. Visual sibling of
/// `LinkedTicketsSection`/`PageSubPagesSection`: same top-bordered block,
/// same header rhythm (caption label + count pill + trailing "+ Add"
/// control). Read-only — there is no remove/retype affordance on a row;
/// the only way to remove an entry is to delete the underlying gap/
/// question ticket elsewhere. Mirrors `LinkedTicketsSection`'s
/// `trailing`-widget shape rather than a plain `onAdd` callback, since
/// the trailing control (`RaiseGapOrQuestionPicker`) owns its own "+ Add"
/// trigger button, `LayerLink`, and `Overlay`, same as `TicketLinkPicker`
/// does for `LinkedTicketsSection`. Added for
/// `aion-arch/changes/idea-gap-question-ticket-types`; see that change's
/// design.md §6.1 and Component Spec §2.
class GapsAndOpenQuestionsSection extends StatelessWidget {
  /// Creates a [GapsAndOpenQuestionsSection] listing [refs].
  const GapsAndOpenQuestionsSection({
    super.key,
    required this.viewedTicketId,
    required this.refs,
    required this.onTap,
    this.trailing,
  });

  /// The currently-viewed ticket's id — compared against each
  /// [GapOrQuestionRef.raisedOn] to tell a directly-raised entry
  /// (`raisedOn.id == viewedTicketId`) from a rolled-up one (raised on a
  /// descendant).
  final String viewedTicketId;

  /// The gap/open-question refs to render — directly-raised entries
  /// (`ref.raisedOn.id == ` the viewed ticket's id) first, then rolled-up
  /// entries, most-relevant order as provided by the caller
  /// (`TicketsCubit.loadDocumentRelations`).
  final List<GapOrQuestionRef> refs;

  /// Called with a row's gap/question ticket id when it's tapped.
  final ValueChanged<String> onTap;

  /// The header's trailing "+ Add" affordance (a `RaiseGapOrQuestionPicker`).
  /// `null` renders no trailing control.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  context.l10n.documentationGapsAndQuestionsLabel,
                  style: AionText.caption.copyWith(color: c.textMuted),
                ),
                if (refs.isNotEmpty) ...[
                  const SizedBox(width: AionSpacing.sp8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.surfaceHover,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      child: Text(
                        '${refs.length}',
                        style: AionText.key.copyWith(color: c.textSecondary),
                      ),
                    ),
                  ),
                ],
                if (trailing != null) ...[const Spacer(), trailing!],
              ],
            ),
            const SizedBox(height: AionSpacing.sp12),
            if (refs.isEmpty)
              _EmptyState(text: context.l10n.documentationGapsAndQuestionsEmpty)
            else
              Column(
                children: [
                  for (final ref in refs) ...[
                    _GapOrQuestionRow(
                      ref: ref,
                      isRolledUp: ref.raisedOn.id != viewedTicketId,
                      onTap: () => onTap(ref.ticket.id),
                    ),
                    if (ref != refs.last) const SizedBox(height: AionSpacing.sp8),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The section's empty-state placeholder — Component Spec §2.5.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border, width: 1),
        borderRadius: const BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        child: Text(
          text,
          style: AionText.bodySm.copyWith(color: c.textSecondary),
        ),
      ),
    );
  }
}

/// A single gap/question row: type-color dot, mono ticket key, title, a
/// subtitle naming the type (and, when [GapOrQuestionRef.raisedOn] is a
/// descendant of the viewed ticket rather than the ticket itself, which
/// specific subtree member it was raised on), and a trailing chevron.
/// Mirrors `LinkedTicketsSection`'s `_LinkRow` visual grammar. Component
/// Spec §2.3/§2.4.
class _GapOrQuestionRow extends StatefulWidget {
  const _GapOrQuestionRow({
    required this.ref,
    required this.isRolledUp,
    required this.onTap,
  });

  final GapOrQuestionRef ref;

  /// Whether [ref] was raised on a descendant of the viewed ticket rather
  /// than the viewed ticket itself — see
  /// `GapsAndOpenQuestionsSection.viewedTicketId`.
  final bool isRolledUp;
  final VoidCallback onTap;

  @override
  State<_GapOrQuestionRow> createState() => _GapOrQuestionRowState();
}

class _GapOrQuestionRowState extends State<_GapOrQuestionRow> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final ref = widget.ref;
    final ticket = ref.ticket;
    final typeColor = ticket.type == TicketType.knownGap
        ? c.typeKnownGap
        : c.typeOpenQuestion;
    final isRaised = _isHovered || _isFocused;
    final typeLabel = ticketTypeLabel(context, ticket.type);
    final subtitle = widget.isRolledUp
        ? '↳ $typeLabel · '
              '${context.l10n.documentationGapsAndQuestionsRaisedOn(ref.raisedOn.title)}'
        : typeLabel;

    return Semantics(
      button: true,
      label: ticket.title,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Focus(
          onFocusChange: (focused) => setState(() => _isFocused = focused),
          child: GestureDetector(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: AnimatedScale(
              scale: _isPressed ? 0.99 : 1.0,
              duration: const Duration(milliseconds: 80),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: isRaised ? c.surfaceHover : c.surface,
                  border: Border.all(
                    color: isRaised ? c.borderStrong : c.border,
                    width: 1,
                  ),
                  borderRadius: const BorderRadius.all(AionRadius.md),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: typeColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const SizedBox(width: 10, height: 10),
                      ),
                      const SizedBox(width: AionSpacing.sp8 + 2),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.surfaceHover,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            ticket.ticketId,
                            style: AionText.key.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AionSpacing.sp8 + 2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              ticket.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AionText.cardTitle.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AionText.bodySm.copyWith(
                                fontSize: 11.5,
                                color: c.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      PhosphorIcon(
                        PhosphorIcons.caretRightLight,
                        size: 16,
                        color: c.textMuted,
                      ),
                    ],
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
