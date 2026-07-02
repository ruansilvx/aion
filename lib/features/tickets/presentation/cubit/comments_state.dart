import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';

sealed class CommentsState extends Equatable {
  const CommentsState();

  @override
  List<Object?> get props => [];
}

class CommentsInitial extends CommentsState {
  const CommentsInitial();
}

class CommentsLoading extends CommentsState {
  const CommentsLoading();
}

class CommentsLoaded extends CommentsState {
  const CommentsLoaded(this.comments);

  final List<TicketComment> comments;

  @override
  List<Object?> get props => [comments];
}

class CommentsError extends CommentsState {
  const CommentsError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class CommentAdding extends CommentsState {
  const CommentAdding(this.comments);

  final List<TicketComment> comments;

  @override
  List<Object?> get props => [comments];
}

class CommentAdded extends CommentsState {
  const CommentAdded(this.comments);

  final List<TicketComment> comments;

  @override
  List<Object?> get props => [comments];
}
