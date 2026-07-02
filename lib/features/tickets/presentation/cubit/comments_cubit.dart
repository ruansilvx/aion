// presentation/cubit/comments_cubit.dart — CommentsCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/domain/repositories/comment_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/comments_state.dart';

/// Loads and posts comments for a single ticket via [CommentRepository].
/// Screen-scoped — a new instance is provided per [TicketDetailScreen], not
/// shared at the app root.
///
/// Comments bypass the watcher scheduled-changes gate: this cubit writes
/// directly to the repository with no review queue (see spec.md and
/// design.md watcher-gate-bypass invariant).
class CommentsCubit extends Cubit<CommentsState> {
  /// Creates a [CommentsCubit] backed by [_repository].
  CommentsCubit(this._repository) : super(const CommentsInitial());

  final CommentRepository _repository;

  /// Fetches all comments for [ticketId]. Emits [CommentsLoading] then
  /// [CommentsLoaded] on success, or [CommentsError] if the repository call
  /// throws.
  Future<void> loadComments(String ticketId) async {
    emit(const CommentsLoading());
    try {
      final comments = await _repository.getCommentsForTicket(ticketId);
      emit(CommentsLoaded(comments));
    } catch (e) {
      emit(CommentsError(e.toString()));
    }
  }

  /// Posts a new comment with [content] on [ticketId], then reloads the
  /// comment list.
  ///
  /// [authorType] defaults to [CommentAuthorType.human]; pass
  /// [CommentAuthorType.ai] with [aiModel] set for AI-authored comments.
  /// Emits [CommentAdding] (carrying the list as it was before this call)
  /// then [CommentAdded] (carrying the refreshed list) on success, or
  /// [CommentsError] if the repository call throws.
  Future<void> addComment({
    required String ticketId,
    required String content,
    CommentAuthorType authorType = CommentAuthorType.human,
    String? aiModel,
  }) async {
    final currentComments = switch (state) {
      CommentsLoaded(:final comments) => comments,
      CommentAdding(:final comments) => comments,
      CommentAdded(:final comments) => comments,
      _ => <TicketComment>[],
    };

    emit(CommentAdding(currentComments));
    try {
      final comment = TicketComment(
        id: '',
        ticketId: ticketId,
        content: content,
        authorType: authorType,
        aiModel: aiModel,
        createdAt: DateTime.now(),
      );

      await _repository.addComment(comment);
      final comments = await _repository.getCommentsForTicket(ticketId);
      emit(CommentAdded(comments));
    } catch (e) {
      emit(CommentsError(e.toString()));
    }
  }
}
