// features/pages/presentation/cubit/pages_cubit.dart — PagesCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/core/contracts/page_ticket_provider.dart';
import 'package:aion/features/pages/presentation/cubit/pages_state.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// UI-orchestration Cubit for the `pages` feature. Mirrors the shape of
/// `TicketsCubit`'s detail/create flows, but scoped to `page` tickets only
/// and built entirely on [PageTicketProvider] — never on `TicketsCubit`
/// or `TicketRepository` directly. Per
/// `aion-arch/changes/page-content-markdown-editor/design.md`.
class PagesCubit extends Cubit<PagesState> {
  /// Creates a [PagesCubit] backed by [_provider].
  PagesCubit(this._provider) : super(const PagesInitial());

  final PageTicketProvider _provider;

  /// Loads the `page` ticket with id [id] plus its sub-pages/linked-
  /// tickets/backlinks. Emits [PagesLoading] then [PageDetailLoaded] on
  /// success, or [PagesError] if the page isn't found or the provider
  /// call throws.
  Future<void> loadPage(String id) async {
    emit(const PagesLoading());
    try {
      final page = await _provider.getPage(id);
      if (page == null) {
        emit(const PagesError('Page not found.'));
        return;
      }
      final relations = await _provider.loadPageRelations(id);
      emit(PageDetailLoaded(page, relations));
    } catch (e) {
      emit(PagesError(e.toString()));
    }
  }

  /// Creates a new page with [title]/[description]/[parentId]. Emits
  /// [PagesLoading] then [PageCreated] on success, or [PagesError] if the
  /// provider call throws.
  Future<void> createPage({
    required String title,
    String? description,
    String? parentId,
  }) async {
    emit(const PagesLoading());
    try {
      final page = await _provider.createPage(
        title: title,
        description: description,
        parentId: parentId,
      );
      emit(PageCreated(page));
    } catch (e) {
      emit(PagesError(e.toString()));
    }
  }

  /// Persists an edited [page], then reloads its relations. Emits
  /// [PageDetailLoaded] with the refreshed page/relations on success, or
  /// [PagesError] if the provider call throws.
  Future<void> updatePage(Ticket page) async {
    try {
      final updated = await _provider.updatePage(page);
      final relations = await _provider.loadPageRelations(updated.id);
      emit(PageDetailLoaded(updated, relations));
    } catch (e) {
      emit(PagesError(e.toString()));
    }
  }

  /// Moves the page with id [id] to trash. Emits [PageTrashed] on
  /// success, or [PagesError] if the provider call throws.
  Future<void> trashPage(String id) async {
    try {
      await _provider.trashPage(id);
      emit(const PageTrashed());
    } catch (e) {
      emit(PagesError(e.toString()));
    }
  }
}
