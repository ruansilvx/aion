// presentation/cubit/documentation_cubit.dart — DocumentationCubit business logic (presentation layer).

import 'dart:async';

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

  /// How long [search] waits after the most recent call before actually
  /// querying — debouncing lives here, not in the calling widget (a
  /// Cubit is not required to be a thin pass-through; this is business
  /// logic, not view rendering).
  static const _searchDebounceDuration = Duration(milliseconds: 250);

  Timer? _searchDebounce;

  /// Bumped on every [search]/[clearSearch] call, so a debounced search
  /// that's since been superseded (a newer keystroke, or a clear) detects
  /// it's stale and drops its result instead of emitting over newer state.
  int _searchGeneration = 0;

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
  /// [clearSearch]. Debounced internally by [_searchDebounceDuration] —
  /// safe to call on every keystroke; only the last call within the
  /// debounce window actually queries. The returned future resolves once
  /// the debounce window elapses and the (possibly superseded) query
  /// finishes, so callers that `await` it still see real completion.
  Future<void> search(String query) {
    _searchDebounce?.cancel();
    final generation = ++_searchGeneration;

    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return clearSearch();
    }

    final completer = Completer<void>();
    _searchDebounce = Timer(_searchDebounceDuration, () async {
      try {
        final results = await _searchService.search(trimmed);
        if (generation == _searchGeneration) {
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
        }
      } catch (e) {
        if (generation == _searchGeneration) {
          emit(DocumentationError(e.toString()));
        }
      } finally {
        completer.complete();
      }
    });
    return completer.future;
  }

  /// Clears the active search, returning the body to tree mode. Cancels
  /// any pending debounced [search] first, so a stale query can never
  /// resolve after a clear and silently re-open search mode. No-ops on
  /// the [DocumentationLoaded] state change if the cubit isn't in that
  /// state with a non-null `searchResults`.
  Future<void> clearSearch() async {
    _searchDebounce?.cancel();
    _searchGeneration++;

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

  @override
  Future<void> close() {
    _searchDebounce?.cancel();
    return super.close();
  }
}
