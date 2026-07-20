// features/pages/presentation/screens/page_detail_screen.dart — PageDetailScreen (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/pages/presentation/cubit/pages_cubit.dart';
import 'package:aion/features/pages/presentation/cubit/pages_state.dart';
import 'package:aion/features/pages/presentation/screens/page_create_screen.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// The `/workspace/pages/:id` route: a `page` ticket's title, Markdown
/// content editor, sub-pages, linked tickets, and backlinks — no
/// priority/estimate/time-spent/status fields, no comment thread (those
/// are work-item-only, see proposal.md's scope boundaries). Builds its
/// own [PagesCubit], backed by the workspace-scoped [PageTicketProvider]
/// read from context. Per
/// `aion-arch/changes/page-content-markdown-editor/design.md` §3.
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

  @override
  void initState() {
    super.initState();
    _cubit = PagesCubit(context.read<PageTicketProvider>());
    _cubit.loadPage(widget.pageId);
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
      child: _PageDetailBody(pageId: widget.pageId),
    );
  }
}

class _PageDetailBody extends StatelessWidget {
  const _PageDetailBody({required this.pageId});

  final String pageId;

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
                      _PageDetailContent(page: page, relations: relations),
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
  const _PageDetailContent({required this.page, required this.relations});

  final Ticket page;
  final PageRelations relations;

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
                  MarkdownEditor(
                    initialValue: page.description ?? '',
                    placeholder: context.l10n.pageDetailContentPlaceholder,
                    semanticsLabel: context.l10n.pageDetailEditContent,
                    onCommit: (v) => context.read<PagesCubit>().updatePage(
                      page.copyWith(description: () => v.isEmpty ? null : v),
                    ),
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
              tickets: relations.linkedTickets,
              onTap: (id) => context.go('/workspace/tickets/$id'),
            ),
            BacklinksSection(
              tickets: relations.backlinks,
              onTap: (id) {
                final ticket = relations.backlinks.firstWhere(
                  (t) => t.id == id,
                  orElse: () => relations.backlinks.first,
                );
                context.go(ticketDetailRoute(ticket));
              },
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
              const TypeChip(type: TicketType.page, isRow: false),
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
