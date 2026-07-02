import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/domain/repositories/comment_repository.dart';

class DriftCommentRepository implements CommentRepository {
  DriftCommentRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  @override
  Future<List<TicketComment>> getCommentsForTicket(String ticketId) async {
    final rows = await _db.commentDao.getCommentsForTicket(ticketId);
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> addComment(TicketComment comment) async {
    final id = comment.id.isEmpty ? _uuid.v4() : comment.id;

    final companion = TicketCommentsTableCompanion.insert(
      id: id,
      ticketId: comment.ticketId,
      content: comment.content,
      authorType: comment.authorType.name,
      aiModel: Value(comment.aiModel),
      createdAt: comment.createdAt.millisecondsSinceEpoch,
    );

    await _db.commentDao.insertComment(companion);
  }

  TicketComment _toEntity(TicketCommentData row) {
    return TicketComment(
      id: row.id,
      ticketId: row.ticketId,
      content: row.content,
      authorType: CommentAuthorType.values.firstWhere(
        (e) => e.name == row.authorType,
        orElse: () => CommentAuthorType.human,
      ),
      aiModel: row.aiModel,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    );
  }
}
