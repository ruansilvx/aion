// presentation/screens/documentation_screen.dart — DocumentationScreen root screen (presentation layer).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/presentation/cubit/documentation_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/documentation_state.dart';
import 'package:aion/features/tickets/presentation/screens/create_ticket_screen.dart';
import 'package:aion/features/tickets/presentation/widgets/documentation_tree_item.dart';

/// The `/workspace/documentation` route: the primary home for `page`/
/// `resource` tickets — a searchable, nestable tree, replacing their
/// presence on the main ticket list/board. [DocumentationCubit] is
/// provided per-route by `appRouter`, same pattern as `TrashCubit`. Per
/// design.md §3.
class DocumentationScreen extends StatefulWidget {
  /// Creates a [DocumentationScreen].
  const DocumentationScreen({super.key});

  @override
  State<DocumentationScreen> createState() => _DocumentationScreenState();
}

class _DocumentationScreenState extends State<DocumentationScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    context.read<DocumentationCubit>().load();
    _searchController.addListener(_handleSearchTextChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_handleSearchTextChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchTextChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      context.read<DocumentationCubit>().search(_searchController.text);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    context.read<DocumentationCubit>().clearSearch();
  }

  void _openTicket(String ticketId) => context.go('/workspace/tickets/$ticketId');

  void _createDoc(TicketType type) {
    context.push(
      '/workspace/tickets/new',
      extra: CreateTicketRouteExtra(initialType: type),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return ColoredBox(
      color: c.background,
      child: Column(
        children: [
          _Header(
            searchController: _searchController,
            onClearSearch: _clearSearch,
            onNewPage: () => _createDoc(TicketType.page),
            onNewResource: () => _createDoc(TicketType.resource),
          ),
          Expanded(
            child: BlocBuilder<DocumentationCubit, DocumentationState>(
              builder: (context, state) {
                return switch (state) {
                  DocumentationLoading() ||
                  DocumentationInitial() => const Center(child: AppSpinner()),
                  DocumentationError(:final message) => Center(
                    child: Text(
                      message,
                      style: AionText.body.copyWith(color: c.danger),
                    ),
                  ),
                  DocumentationLoaded(:final searchResults) =>
                    searchResults != null
                        ? _SearchResultsBody(
                            query: _searchController.text.trim(),
                            results: searchResults,
                            onTap: _openTicket,
                          )
                        : _TreeBody(state: state, onTap: _openTicket),
                };
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Header block: eyebrow, title + avatar row, "+ New page"/"+ New
/// resource" actions, and the search field. Per design.md §3.1/§3.2.
class _Header extends StatelessWidget {
  const _Header({
    required this.searchController,
    required this.onClearSearch,
    required this.onNewPage,
    required this.onNewResource,
  });

  final TextEditingController searchController;
  final VoidCallback onClearSearch;
  final VoidCallback onNewPage;
  final VoidCallback onNewResource;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.documentationEyebrow,
                  style: AionText.caption.copyWith(color: c.textMuted),
                ),
                const SizedBox(height: AionSpacing.sp4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.documentationTitle,
                        style: AionText.h1.copyWith(color: c.textPrimary),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.surfaceHover,
                        border: Border.all(color: c.border, width: 1),
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: Center(
                          child: Text(
                            'U',
                            style: AionText.key.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    AppButton(
                      label: context.l10n.documentationNewPageAction,
                      icon: PhosphorIcons.plusLight,
                      onPressed: onNewPage,
                    ),
                    const SizedBox(width: AionSpacing.sp8),
                    AppButton(
                      label: context.l10n.documentationNewResourceAction,
                      icon: PhosphorIcons.plusLight,
                      variant: AppButtonVariant.secondary,
                      onPressed: onNewResource,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
            child: _SearchField(
              controller: searchController,
              onClear: onClearSearch,
            ),
          ),
        ],
      ),
    );
  }
}

/// The Documentation section's search field — [AppTextField]'s
/// leading-icon variant, plus a trailing clear affordance shown whenever
/// the field is non-empty. Not a promoted design-system component (per
/// design.md §6, this stays local to Documentation until a second feature
/// needs it).
class _SearchField extends StatefulWidget {
  const _SearchField({required this.controller, required this.onClear});

  final TextEditingController controller;
  final VoidCallback onClear;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleChange);
    super.dispose();
  }

  void _handleChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Stack(
      alignment: Alignment.centerRight,
      children: [
        AppTextField(
          controller: widget.controller,
          hintText: context.l10n.documentationSearchHint,
          prefixIcon: PhosphorIcon(
            PhosphorIcons.magnifyingGlassLight,
            size: 18,
            color: c.textMuted,
          ),
        ),
        if (widget.controller.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Semantics(
              button: true,
              label: context.l10n.documentationClearSearchAction,
              child: GestureDetector(
                onTap: widget.onClear,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surfaceHover,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: Center(
                      child: PhosphorIcon(
                        PhosphorIcons.xLight,
                        size: 11,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Tree-mode body: root docs, each expandable if it's a `page` with
/// children. Renders [DocumentationEmptyState] when there are zero root
/// docs. Per design.md §3.3/§7.
class _TreeBody extends StatelessWidget {
  const _TreeBody({required this.state, required this.onTap});

  final DocumentationLoaded state;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (state.rootDocs.isEmpty) {
      return _EmptyState(
        onNewPage: () => context.push(
          '/workspace/tickets/new',
          extra: const CreateTicketRouteExtra(initialType: TicketType.page),
        ),
      );
    }

    final t = ThemeScope.of(context);
    final c = t.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border, width: 1)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          for (final doc in state.rootDocs)
            _TreeNode(
              ticket: doc,
              depth: 0,
              state: state,
              onTap: onTap,
            ),
        ],
      ),
    );
  }
}

/// Recursively renders [ticket] and, if it's an expanded `page`, its
/// cached children beneath it.
class _TreeNode extends StatelessWidget {
  const _TreeNode({
    required this.ticket,
    required this.depth,
    required this.state,
    required this.onTap,
  });

  final Ticket ticket;
  final int depth;
  final DocumentationLoaded state;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final isPage = ticket.type == TicketType.page;
    final isExpanded = state.expandedIds.contains(ticket.id);
    final children = state.childrenByParentId[ticket.id];

    return Column(
      children: [
        DocumentationTreeItem(
          ticket: ticket,
          depth: depth,
          isExpanded: isExpanded,
          childCount: isPage && !isExpanded ? children?.length : null,
          onTap: () => onTap(ticket.id),
          onToggleExpand: isPage
              ? () => context.read<DocumentationCubit>().loadChildren(
                  ticket.id,
                )
              : null,
        ),
        if (isPage && isExpanded && children != null)
          for (final child in children)
            _TreeNode(
              ticket: child,
              depth: depth + 1,
              state: state,
              onTap: onTap,
            ),
      ],
    );
  }
}

/// Flat, ranked search-result body. Per design.md §3.4.
class _SearchResultsBody extends StatelessWidget {
  const _SearchResultsBody({
    required this.query,
    required this.results,
    required this.onTap,
  });

  final String query;
  final List<Ticket> results;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                PhosphorIcons.magnifyingGlassLight,
                size: 20,
                color: c.textMuted,
              ),
              const SizedBox(height: AionSpacing.sp12),
              Text(
                context.l10n.documentationNoResults(query),
                textAlign: TextAlign.center,
                style: AionText.body.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border, width: 1)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: Text(
              context.l10n.documentationResultsCount(results.length),
              style: AionText.caption.copyWith(color: c.textMuted),
            ),
          ),
          for (final result in results)
            DocumentationTreeItem(
              ticket: result,
              showChevron: false,
              onTap: () => onTap(result.id),
            ),
        ],
      ),
    );
  }
}

/// Zero-docs empty state — filled emblem, heading, supporting copy, and a
/// primary "+ New page" action. Mirrors `EmptyHubState`'s composition
/// rather than design.md §7's literal hexagon clip-path, matching the
/// simpler emblem convention this app already ships. Per design.md §7.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onNewPage});

  final VoidCallback onNewPage;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.primary.withValues(alpha: t.isDark ? 0.50 : 0.32),
                      borderRadius: BorderRadius.all(AionRadius.xl),
                      boxShadow: [
                        BoxShadow(
                          color: c.primary.withValues(
                            alpha: t.isDark ? 0.50 : 0.32,
                          ),
                          blurRadius: 28,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const SizedBox(width: 84, height: 84),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(width: 80, height: 80),
                  ),
                  const PhosphorIcon(
                    PhosphorIcons.bookOpenLight,
                    size: 36,
                    color: Color(0xFFFFFFFF),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              context.l10n.documentationEmptyTitle,
              textAlign: TextAlign.center,
              style: AionText.h2.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: AionSpacing.sp8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                context.l10n.documentationEmptyBody,
                textAlign: TextAlign.center,
                style: AionText.body.copyWith(
                  color: c.textSecondary,
                  height: 1.55,
                ),
              ),
            ),
            const SizedBox(height: AionSpacing.sp24),
            AppButton(
              label: context.l10n.documentationNewPageAction,
              icon: PhosphorIcons.plusLight,
              onPressed: onNewPage,
            ),
          ],
        ),
      ),
    );
  }
}
