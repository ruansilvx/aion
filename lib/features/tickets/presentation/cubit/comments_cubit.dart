import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/domain/repositories/comment_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/comments_state.dart';

// Comments bypass the watcher scheduled-changes gate: this cubit writes
// directly to the repository with no review queue (see spec.md and
// design.md watcher-gate-bypass invariant).
class CommentsCubit extends Cubit<CommentsState> {
  CommentsCubit(this._repository) : super(const CommentsInitial());

  final CommentRepository _repository;

  Future<void> loadComments(String ticketId) async {
    emit(const CommentsLoading());
    try {
      final comments = await _repository.getCommentsForTicket(ticketId);
      emit(CommentsLoaded(comments));
    } catch (e) {
      emit(CommentsError(e.toString()));
    }
  }

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
