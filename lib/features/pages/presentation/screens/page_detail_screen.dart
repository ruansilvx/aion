// features/pages/presentation/screens/page_detail_screen.dart — PageDetailScreen (presentation layer).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/core/markdown/wikilink_extractor.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/pages/presentation/cubit/pages_cubit.dart';
import 'package:aion/features/pages/presentation/cubit/pages_state.dart';
import 'package:aion/features/pages/presentation/screens/page_create_screen.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_parent_picker.dart'
    show ancestorBreadcrumb;

/// The `/workspace/pages/:id` route: a `page`/`spec` ticket's title,
/// Markdown content editor, sub-pages, linked tickets, backlinks, and
/// gaps/open questions — no priority/estimate/time-spent/status fields,
/// no comment thread (those are work-item-only, see proposal.md's scope
/// boundaries). Builds its
/// own [PagesCubit], backed by the workspace-scoped [PageTicketProvider]
/// read from context. Per
/// `AIO-1350` §3. Widened
/// to also serve [TicketType.spec] for
/// `AIO-1998` — a spec ticket is edited exactly
/// like a page, plus one spec-only addition: [_SpecOriginBadge] at the
/// top of the scroll body.
class PageDetailScreen extends StatefulWidget {
  /// Creates a [PageDetailScreen] for the page with internal id [pageId].
  const PageDetailScreen({super.key, required this.pageId});

  /// Internal UUID of the page ticket to display.
  final String pageId;

  @override
  State<PageDetailScreen> createState() => _PageDetailScreenState();
}

class _PageDetailScreenState extends State<PageDetailScreen> {
  late final PagesCubit _cubit;

  /// Every live `page`/`resource` ticket, fetched once and cached here —
  /// the wikilink-autocomplete/resolution candidate list. `null` while
  /// the initial fetch is in flight. Per
  /// `AIO-963`'s
  /// "no re-fetch per keystroke" precedent.
  List<Ticket>? _wikilinkCandidates;

  @override
  void initState() {
    super.initState();
    _cubit = PagesCubit(context.read<PageTicketProvider>());
    _cubit.loadPage(widget.pageId);
    unawaited(_loadWikilinkCandidates());
  }

  Future<void> _loadWikilinkCandidates() async {
    final candidates = await _cubit.loadWikilinkCandidates();
    if (!mounted) return;
    setState(() => _wikilinkCandidates = candidates);
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PagesCubit>.value(
      value: _cubit,
      child: _PageDetailBody(
        pageId: widget.pageId,
        wikilinkCandidates: _wikilinkCandidates,
      ),
    );
  }
}

class _PageDetailBody extends StatelessWidget {
  const _PageDetailBody({required this.pageId, required this.wikilinkCandidates});

  final String pageId;

  /// See [_PageDetailScreenState._wikilinkCandidates]'s dartdoc.
  final List<Ticket>? wikilinkCandidates;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return BlocListener<PagesCubit, PagesState>(
      listener: (context, state) {
        if (state is PageTrashed) {
          context.go('/workspace/documentation');
        } else if (state is PagesError) {
          AppToast.show(context, state.message);
        }
      },
      child: ColoredBox(
        color: c.background,
        child: Column(
          children: [
            BlocBuilder<PagesCubit, PagesState>(
              builder: (context, state) {
                final page = state is PageDetailLoaded ? state.page : null;
                return _PageDetailHeader(
                  page: page,
                  onBack: () => context.go('/workspace/documentation'),
                );
              },
            ),
            Expanded(
              child: BlocBuilder<PagesCubit, PagesState>(
                builder: (context, state) {
                  return switch (state) {
                    PagesLoading() || PagesInitial() => const Center(
                      child: AppSpinner(),
                    ),
                    PagesError(:final message) => Center(
                      child: Text(
                        message,
                        style: AionText.body.copyWith(color: c.danger),
                      ),
                    ),
                    PageDetailLoaded(:final page, :final relations) =>
                      _PageDetailContent(
                        page: page,
                        relations: relations,
                        wikilinkCandidates: wikilinkCandidates,
                      ),
                    _ => const SizedBox.shrink(),
                  };
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageDetailContent extends StatelessWidget {
  const _PageDetailContent({
    required this.page,
    required this.relations,
    required this.wikilinkCandidates,
  });

  final Ticket page;
  final PageRelations relations;

  /// See [_PageDetailScreenState._wikilinkCandidates]'s dartdoc.
  final List<Ticket>? wikilinkCandidates;

  /// Case-insensitive substring filter (capped 20) over
  /// [wikilinkCandidates], mapped to [WikilinkSuggestionItem] — design.md
  /// §7. `null`/empty candidates (not yet loaded) yields no suggestions,
  /// leaving `[[` inert until the fetch resolves.
  List<WikilinkSuggestionItem> _wikilinkSuggestionsFor(String query) {
    final candidates = wikilinkCandidates;
    if (candidates == null) return const [];
    final byId = {for (final t in candidates) t.id: t};
    final q = query.trim().toLowerCase();
    final matches = q.isEmpty
        ? candidates
        : candidates.where((t) => t.title.toLowerCase().contains(q)).toList();
    return matches
        .take(20)
        .map(
          (t) => WikilinkSuggestionItem(
            ticketId: t.ticketId,
            title: t.title,
            breadcrumb: ancestorBreadcrumb(t, byId),
          ),
        )
        .toList();
  }

  /// Resolves a wikilink match's [target] against [wikilinkCandidates] —
  /// id match first (per [WikilinkExtractor.looksLikeTicketId]), else
  /// case-insensitive title match — design.md §7.
  Ticket? _resolveWikilink(String target) {
    final candidates = wikilinkCandidates;
    if (candidates == null) return null;
    if (WikilinkExtractor.looksLikeTicketId(target)) {
      for (final t in candidates) {
        if (t.ticketId == target) return t;
      }
      return null;
    }
    final targetLower = target.toLowerCase();
    for (final t in candidates) {
      if (t.title.toLowerCase() == targetLower) return t;
    }
    return null;
  }

  /// Creates a new page titled [title] as a child of [page], for both the
  /// autocomplete's no-matches state and an unresolved rendered span's
  /// tap-to-create affordance. Goes through [PageTicketProvider] directly
  /// rather than `context.read<PagesCubit>().createPage(...)` — this
  /// screen's own [PagesCubit] instance drives its entire render state
  /// (see the `BlocBuilder` in [_PageDetailBody]), so routing this
  /// side-flow through it would emit `PagesLoading`/`PageCreated` and
  /// blank the screen currently being edited; [PageTicketProvider
  /// .createPage] is the exact same call `PagesCubit.createPage`
  /// delegates to, just without that emission. Does not refresh
  /// [wikilinkCandidates] — the newly created page won't appear in a
  /// later `[[` autocomplete until this screen is reopened, a documented
  /// simplification.
  Future<Ticket> _createLinkedPage(BuildContext context, String title) {
    return context.read<PageTicketProvider>().createPage(
      title: title,
      parentId: page.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: ContentMaxWidth(
        variant: ContentWidthVariant.reading,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // `_SpecOriginBadge` — spec-only, first child of the
                  // scroll body, per design.md §3.2. Not built at all for
                  // a `page` ticket (no stray gap left behind) — the
                  // `if` below skips both the badge and its own sp16
                  // spacer together, rather than leaving a zero-height
                  // widget inside this spaced Column. Added for
                  // `AIO-1998`.
                  if (page.type == TicketType.spec) ...[
                    _SpecOriginBadge(ticket: page, relations: relations),
                    const SizedBox(height: AionSpacing.sp16),
                  ],
                  MarkdownEditor(
                    initialValue: page.description ?? '',
                    placeholder: context.l10n.pageDetailContentPlaceholder,
                    semanticsLabel: context.l10n.pageDetailEditContent,
                    onCommit: (v) => context.read<PagesCubit>().updatePage(
                      page.copyWith(description: () => v.isEmpty ? null : v),
                    ),
                    wikilinkSuggestions: _wikilinkSuggestionsFor,
                    onCreatePage: (title) async {
                      final created = await _createLinkedPage(context, title);
                      return WikilinkSuggestionItem(
                        ticketId: created.ticketId,
                        title: created.title,
                      );
                    },
                    resolveWikilink: _resolveWikilink,
                    onWikilinkTap: (ticket) =>
                        context.go(ticketDetailRoute(ticket)),
                    onCreateWikilinkTarget: (title) async {
                      final created = await _createLinkedPage(context, title);
                      if (context.mounted) {
                        context.go(ticketDetailRoute(created));
                      }
                    },
                  ),
                ],
              ),
            ),
            PageSubPagesSection(
              childDocs: relations.childDocs,
              onTap: (id) => context.go('/workspace/pages/$id'),
              onAdd: () => context.push(
                '/workspace/pages/new',
                extra: PageCreateRouteExtra(initialParentId: page.id),
              ),
            ),
            LinkedTicketsSection(
              links: relations.linkedTickets,
              // No creatable link types for a page's own Linked Tickets
              // section — pages never render `TicketLinkPicker` as this
              // section's `trailing` (see below), so link *creation*
              // stays out of scope here, per proposal.md's Non-goals.
              // In-place *editing* of an existing row's type still
              // applies, though, with the same widened non-`resource`
              // option set `ticket_metadata_section.dart` offers for
              // every board-ticket type a page can link to.
              linkTypeOptions: const [
                TicketLinkType.blocks,
                TicketLinkType.blockedBy,
                TicketLinkType.relatesTo,
                TicketLinkType.duplicates,
              ],
              onTap: (id) => context.go('/workspace/tickets/$id'),
              onRemove: (linkId) =>
                  context.read<PagesCubit>().deleteLink(page.id, linkId),
              onChangeType: (linkId, newRelativeType) => context
                  .read<PagesCubit>()
                  .updateLinkType(page.id, linkId, newRelativeType),
            ),
            BacklinksSection(
              backlinks: relations.backlinks,
              onTap: (id) {
                final backlinkTickets = relations.backlinks
                    .map((r) => r.ticket)
                    .toList();
                final ticket = backlinkTickets.firstWhere(
                  (t) => t.id == id,
                  orElse: () => backlinkTickets.first,
                );
                context.go(ticketDetailRoute(ticket));
              },
            ),
            GapsAndOpenQuestionsSection(
              viewedTicketId: page.id,
              refs: relations.gapsAndOpenQuestions,
              onTap: (id) => context.go('/workspace/tickets/$id'),
              trailing: RaiseGapOrQuestionPicker(
                onCreate: (type, {required title, description}) => context
                    .read<PagesCubit>()
                    .createGapOrQuestion(
                      page.id,
                      type,
                      title: title,
                      description: description,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `PageDetailScreen`'s header: back button, [TypeChip] ("PAGE"), an
/// inline-editable title (with the mono `ticketId` as a small eyebrow above
/// it), the sync-status badge, and the delete action — per design.md §3.1.
/// Unlike other screens, this can't reuse [AppHeader] as-is: the title slot
/// here needs to be an editable field with an eyebrow above it, not a
/// plain string. [page] is `null` while the page is still loading.
class _PageDetailHeader extends StatelessWidget {
  /// Creates a [_PageDetailHeader] for [page] (`null` while loading).
  const _PageDetailHeader({required this.page, required this.onBack});

  /// The loaded page, or `null` while [PagesCubit.loadPage] is in flight.
  final Ticket? page;

  /// Called when the back button is tapped.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final page = this.page;

    return ColoredBox(
      color: c.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Semantics(
              label: context.l10n.commonBack,
              button: true,
              child: GestureDetector(
                onTap: onBack,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surfaceHover,
                    border: Border.all(color: c.border, width: 1),
                    borderRadius: const BorderRadius.all(AionRadius.iconBtn),
                  ),
                  child: SizedBox(
                    width: 37,
                    height: 37,
                    child: Center(
                      child: PhosphorIcon(
                        PhosphorIcons.caretLeftLight,
                        size: 18,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AionSpacing.sp12),
            if (page != null) ...[
              // `page.type` (not the hardcoded `TicketType.page`) so a
              // TicketType.spec ticket renders its own "SPEC" chip here —
              // added for `AIO-1998`.
              TypeChip(type: page.type, isRow: false),
              const SizedBox(width: AionSpacing.sp12),
            ],
            Expanded(
              child: page == null
                  ? Text('…', style: AionText.h2.copyWith(color: c.textPrimary))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          page.ticketId,
                          style: AionText.key.copyWith(color: c.textSecondary),
                        ),
                        const SizedBox(height: AionSpacing.sp4),
                        InlineEditableField<String>(
                          displayText: page.title,
                          editText: page.title,
                          maxLines: 1,
                          textStyle: AionText.h2.copyWith(
                            color: c.textPrimary,
                          ),
                          placeholder: context.l10n.pageDetailTitlePlaceholder,
                          semanticsLabel: context.l10n.ticketDetailEditTitle,
                          parser: (raw) {
                            final trimmed = raw.trim();
                            if (trimmed.isEmpty) {
                              throw FormatException(
                                context.l10n.ticketDetailTitleEmptyError,
                              );
                            }
                            return trimmed;
                          },
                          onCommit: (v) => context
                              .read<PagesCubit>()
                              .updatePage(page.copyWith(title: v)),
                        ),
                      ],
                    ),
            ),
            if (page != null) ...[
              const SizedBox(width: AionSpacing.sp12),
              SyncStatusBadge(status: page.syncStatus),
              const SizedBox(width: 12),
              DeleteActionButton(
                semanticsLabel: context.l10n.ticketDeleteMenuItem,
                confirmTitle: context.l10n.ticketDeleteConfirmTitle,
                confirmMessage: context.l10n.ticketTrashConfirmMessage(1),
                confirmLabel: context.l10n.ticketDeleteConfirmAction,
                onConfirmed: () =>
                    context.read<PagesCubit>().trashPage(page.id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small, single-line identity strip shown only when [ticket.type] is
/// [TicketType.spec] — answers one question: did Aion write this, and
/// from what? Per design.md §2.1, resolves two variants from [relations]
/// (rather than a persisted `sourceEpicId` field, which this change's
/// `tasks.md` never adds one for): **auto**, when [relations.linkedTickets]
/// carries a `relatesTo` link to a live [TicketType.epic] ticket —
/// created by `TicketsCubit._createEpicSpec` — rendered as a tappable
/// link to that Epic; **manual**, when no such link is found. This
/// collapses design.md §2.1's third ("orphaned — auto-generated from a
/// deleted Epic") variant into the manual one: trashing an Epic cascades
/// its `TicketLink` rows (`DriftTicketRepository.trashTickets`), so a
/// spec whose Epic was later trashed loses the link entirely rather than
/// keeping a now-dangling reference — the two states are genuinely
/// indistinguishable under a link-based lookup, so there is nothing
/// left to render a distinct third variant for. Noted here rather than
/// silently, per this codebase's convention for a deliberate
/// simplification (see `_PendingSkillAttachmentBanner`'s own dartdoc for
/// the same pattern). The Epic link itself is an `InteractiveLinkSpan`
/// (`design_system/molecules/interactive_link_span.dart`), implementing
/// design.md §2.4.1's full hover/focused/pressed state table — a `/verify`
/// fix-up: the first `/apply` pass used a plain `TextSpan` +
/// `TapGestureRecognizer` here instead, citing `MarkdownView`'s wikilink
/// span as precedent for skipping the interaction states, but that span
/// had the identical gap, so `MarkdownView` was retrofitted onto the same
/// widget in the same fix-up rather than left as false precedent. Renders
/// nothing (not even a zero-height box) unless [ticket.type] is
/// [TicketType.spec] — see design.md §3.3. Added for
/// `AIO-1998`.
class _SpecOriginBadge extends StatelessWidget {
  /// Creates a [_SpecOriginBadge] for [ticket], resolving its origin from
  /// [relations].
  const _SpecOriginBadge({required this.ticket, required this.relations});

  /// The loaded ticket — the badge is inert unless this is a
  /// [TicketType.spec] ticket.
  final Ticket ticket;

  /// [ticket]'s already-loaded Documentation-section relations, reused
  /// here to find the `relatesTo`-linked Epic without a second query.
  final PageRelations relations;

  @override
  Widget build(BuildContext context) {
    if (ticket.type != TicketType.spec) return const SizedBox.shrink();

    final t = ThemeScope.of(context);
    final c = t.colors;
    final sc = c.typeSpec;

    final sourceEpic = relations.linkedTickets
        .where(
          (link) =>
              link.relativeType == TicketLinkType.relatesTo &&
              link.ticket.type == TicketType.epic,
        )
        .map((link) => link.ticket)
        .firstOrNull;

    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: sc.withValues(alpha: t.isDark ? 0.10 : 0.07),
          border: Border.all(
            color: sc.withValues(alpha: t.isDark ? 0.28 : 0.20),
            width: 1,
          ),
          borderRadius: BorderRadius.all(AionRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 5, 12, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: sc.withValues(alpha: t.isDark ? 0.22 : 0.15),
                  borderRadius: BorderRadius.all(AionRadius.sm),
                ),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: Center(
                    child: PhosphorIcon(
                      PhosphorIcons.checkSquareLight,
                      size: 12,
                      color: sc,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AionSpacing.sp8),
              Flexible(
                child: sourceEpic == null
                    ? Text(
                        context.l10n.specOriginBadgeManual,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AionText.breadcrumb.copyWith(
                          color: c.textMuted,
                        ),
                      )
                    : Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: context.l10n.specOriginBadgeAutoPrefix,
                              style: AionText.breadcrumb.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                            // Real hover/focused/pressed states (design.md
                            // §2.4.1), via the shared `InteractiveLinkSpan`
                            // precedent — see that widget's own dartdoc.
                            // Added for
                            // `AIO-1998`'s
                            // `/verify` fix-up (previously a plain static-
                            // underline `TextSpan`).
                            WidgetSpan(
                              alignment: PlaceholderAlignment.baseline,
                              baseline: TextBaseline.alphabetic,
                              child: InteractiveLinkSpan(
                                text: sourceEpic.title,
                                style: AionText.breadcrumb.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                color: c.primary,
                                hoverColor: c.primaryHover,
                                onTap: () =>
                                    context.go(ticketDetailRoute(sourceEpic)),
                                semanticsLabel: sourceEpic.title,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
