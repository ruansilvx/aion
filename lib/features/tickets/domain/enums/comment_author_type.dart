// domain/enums/comment_author_type.dart — CommentAuthorType enum (domain layer).

/// Who authored a [TicketComment](../entities/ticket_comment.dart).
///
/// Drives the visual distinction between human and AI comments in the
/// comment list UI.
enum CommentAuthorType {
  /// Authored by a human user.
  human,

  /// Authored by an AI model. [TicketComment.aiModel] identifies which one.
  ai,
}
