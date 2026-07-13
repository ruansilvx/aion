// domain/entities/ticket_comment.dart — TicketComment entity (domain layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';

/// An append-only note attached to a [Ticket](ticket.dart).
///
/// Comments have no `updatedAt` and no edit/delete path — immutability is
/// structural. They bypass the watcher scheduled-changes gate entirely: a
/// comment is an observation about ticket state, not a proposed change to it.
class TicketComment extends Equatable {
  /// UUID v4 primary key.
  final String id;

  /// UUID of the [Ticket] this comment belongs to.
  final String ticketId;

  /// Plain-text comment body.
  final String content;

  /// Whether a human or an AI model wrote this comment.
  final CommentAuthorType authorType;

  /// Which AI model authored the comment. Non-null only when [authorType]
  /// is [CommentAuthorType.ai].
  final String? aiModel;

  /// When the comment was posted.
  final DateTime createdAt;

  /// Creates a [TicketComment].
  const TicketComment({
    required this.id,
    required this.ticketId,
    required this.content,
    required this.authorType,
    this.aiModel,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
    id,
    ticketId,
    content,
    authorType,
    aiModel,
    createdAt,
  ];
}
