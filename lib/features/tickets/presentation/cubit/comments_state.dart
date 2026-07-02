// presentation/cubit/comments_state.dart — CommentsState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';

/// The state emitted by [CommentsCubit].
sealed class CommentsState extends Equatable {
  const CommentsState();

  @override
  List<Object?> get props => [];
}

/// Before [CommentsCubit.loadComments] has been called.
class CommentsInitial extends CommentsState {
  /// Creates a [CommentsInitial] state.
  const CommentsInitial();
}

/// The comment list fetch is in flight. UI should show [AppSpinner].
class CommentsLoading extends CommentsState {
  /// Creates a [CommentsLoading] state.
  const CommentsLoading();
}

/// The comment list loaded successfully. Carries the full list to render.
class CommentsLoaded extends CommentsState {
  /// Creates a [CommentsLoaded] state carrying [comments].
  const CommentsLoaded(this.comments);

  /// All comments for the ticket, oldest first.
  final List<TicketComment> comments;

  @override
  List<Object?> get props => [comments];
}

/// The comment list fetch or an add-comment call failed. Carries a
/// user-facing error message.
class CommentsError extends CommentsState {
  /// Creates a [CommentsError] state carrying [message].
  const CommentsError(this.message);

  /// A user-facing description of what went wrong.
  final String message;

  @override
  List<Object?> get props => [message];
}

/// A [CommentsCubit.addComment] call is in flight. Carries the
/// previously-loaded list so the comment thread stays visible while posting.
class CommentAdding extends CommentsState {
  /// Creates a [CommentAdding] state carrying the in-flight [comments] list.
  const CommentAdding(this.comments);

  /// The list as it was before this add started.
  final List<TicketComment> comments;

  @override
  List<Object?> get props => [comments];
}

/// A comment was added successfully. Carries the refreshed list (including
/// the new comment).
class CommentAdded extends CommentsState {
  /// Creates a [CommentAdded] state carrying the refreshed [comments] list.
  const CommentAdded(this.comments);

  /// The full list, including the newly added comment.
  final List<TicketComment> comments;

  @override
  List<Object?> get props => [comments];
}
