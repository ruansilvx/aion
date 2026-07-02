import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';

abstract interface class CommentRepository {
  Future<List<TicketComment>> getCommentsForTicket(String ticketId);

  /// Append-only. Throws if attempting to modify an existing comment id.
  Future<void> addComment(TicketComment comment);
}
