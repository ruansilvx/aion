// presentation/cubit/documentation_cubit.dart — DocumentationCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/features/tickets/data/services/ticket_document_search_service.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/documentation_state.dart';

/// Loads and searches the Documentation section's `page`/`resource` tree
/// via [TicketRepository] and [TicketDocumentSearchService]. Provided
/// per-route (fresh on entering `/workspace/documentation`), not
/// root-scoped — the tree doesn't need to survive navigating away, same
/// pattern as `TrashCubit`.
class DocumentationCubit extends Cubit<DocumentationState> {
  /// Creates a [DocumentationCubit] backed by [_repository] and
  /// [_searchService].
  DocumentationCubit(this._repository, this._searchService)
    : super(const DocumentationInitial());

  final TicketRepository _repository;
  final TicketDocumentSearchService _searchService;

  /// Types the Documentation section shows — never board tickets.
  static const _documentTypes = [TicketType.page, TicketType.resource];

  /// Fetches every root-level (`parentId == null`) `page`/`resource`
  /// ticket. Emits [DocumentationLoading] then [DocumentationLoaded] (with
  /// an empty `childrenByParentId`/`expandedIds`, no active search) on
  /// success, or [DocumentationError] if the repository call throws.
  Future<void> load() async {
    emit(const DocumentationLoading());
    try {
      final roots = await _repository.getTicketsByParent(
        null,
        types: _documentTypes,
      );
      emit(
        DocumentationLoaded(
          rootDocs: roots,
          childrenByParentId: const {},
          expandedIds: const {},
        ),
      );
    } catch (e) {
      emit(DocumentationError(e.toString()));
    }
  }

  /// Toggles [pageId]'s expanded state. If newly expanding and its
  /// children haven't been fetched yet, lazily loads and caches them via
  /// [TicketRepository.getTicketsByParent]. No-ops if the cubit isn't in
  /// [DocumentationLoaded] or a search is currently active (the flat
  /// search-result view has no expand/collapse affordance).
  Future<void> loadChildren(String pageId) async {
    final current = state;
    if (current is! DocumentationLoaded || current.searchResults != null) {
      return;
    }

    if (current.expandedIds.contains(pageId)) {
      emit(
        DocumentationLoaded(
          rootDocs: current.rootDocs,
          childrenByParentId: current.childrenByParentId,
          expandedIds: {...current.expandedIds}..remove(pageId),
          searchResults: current.searchResults,
        ),
      );
      return;
    }

    final expanded = {...current.expandedIds, pageId};
    if (current.childrenByParentId.containsKey(pageId)) {
      emit(
        DocumentationLoaded(
          rootDocs: current.rootDocs,
          childrenByParentId: current.childrenByParentId,
          expandedIds: expanded,
          searchResults: current.searchResults,
        ),
      );
      return;
    }

    try {
      final children = await _repository.getTicketsByParent(
        pageId,
        types: _documentTypes,
      );
      final latest = state;
      if (latest is! DocumentationLoaded) return;
      emit(
        DocumentationLoaded(
          rootDocs: latest.rootDocs,
          childrenByParentId: {...latest.childrenByParentId, pageId: children},
          expandedIds: {...latest.expandedIds, pageId},
          searchResults: latest.searchResults,
        ),
      );
    } catch (e) {
      emit(DocumentationError(e.toString()));
    }
  }

  /// Runs an embedding-ranked search for [query] via
  /// [TicketDocumentSearchService.search], switching the body into flat
  /// search-result mode. An empty/whitespace-only [query] is equivalent to
  /// [clearSearch]. No debounce here — the calling screen debounces
  /// keystrokes before invoking this, same pattern as
  /// `TicketsListScreen`'s own search field.
  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      await clearSearch();
      return;
    }

    try {
      final results = await _searchService.search(trimmed);
      final current = state;
      final base = current is DocumentationLoaded
          ? current
          : const DocumentationLoaded(
              rootDocs: [],
              childrenByParentId: {},
              expandedIds: {},
            );
      emit(
        DocumentationLoaded(
          rootDocs: base.rootDocs,
          childrenByParentId: base.childrenByParentId,
          expandedIds: base.expandedIds,
          searchResults: results,
        ),
      );
    } catch (e) {
      emit(DocumentationError(e.toString()));
    }
  }

  /// Clears the active search, returning the body to tree mode. No-ops if
  /// the cubit isn't in [DocumentationLoaded] with a non-null
  /// `searchResults`.
  Future<void> clearSearch() async {
    final current = state;
    if (current is! DocumentationLoaded || current.searchResults == null) {
      return;
    }
    emit(
      DocumentationLoaded(
        rootDocs: current.rootDocs,
        childrenByParentId: current.childrenByParentId,
        expandedIds: current.expandedIds,
      ),
    );
  }
}
