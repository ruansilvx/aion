// domain/repositories/comment_repository.dart — CommentRepository interface (domain layer).

import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';

/// Read/write access to [TicketComment] persistence. Append-only by
/// contract — no update or delete method is exposed.
abstract interface class CommentRepository {
  /// Returns all comments for [ticketId], ordered by [TicketComment.createdAt]
  /// ascending.
  Future<List<TicketComment>> getCommentsForTicket(String ticketId);

  /// Appends [comment]. Throws if attempting to modify an existing comment id.
  Future<void> addComment(TicketComment comment);
}
