import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';

class TicketComment extends Equatable {
  final String id;
  final String ticketId;
  final String content;
  final CommentAuthorType authorType;
  final String? aiModel;
  final DateTime createdAt;

  const TicketComment({
    required this.id,
    required this.ticketId,
    required this.content,
    required this.authorType,
    this.aiModel,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, ticketId, content, authorType, aiModel, createdAt];
}
