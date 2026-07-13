// data/daos/comment_dao.dart — CommentDao Drift accessor (data layer).

import 'package:drift/drift.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/data/models/ticket_comment_model.dart';

part 'comment_dao.g.dart';

/// Drift accessor for [TicketCommentsTable]. Append-only by construction —
/// no UPDATE method is exposed, and the sole DELETE method exists only to
/// cascade-delete a ticket's comments when the ticket itself is deleted.
@DriftAccessor(tables: [TicketCommentsTable])
class CommentDao extends DatabaseAccessor<AppDatabase> with _$CommentDaoMixin {
  /// Creates a [CommentDao] bound to [db].
  CommentDao(super.db);

  /// Returns all comments for [ticketId], ordered by `created_at` ascending.
  Future<List<TicketCommentData>> getCommentsForTicket(String ticketId) {
    return (select(ticketCommentsTable)
          ..where((t) => t.ticketId.equals(ticketId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// Appends [entry] as a new comment row.
  Future<void> insertComment(TicketCommentsTableCompanion entry) {
    return into(ticketCommentsTable).insert(entry);
  }

  /// Deletes every comment row for [ticketId]. The one exception to this
  /// DAO's append-only-by-construction rule (see class doc) — ticket
  /// deletion is the sole caller.
  Future<void> deleteCommentsForTicket(String ticketId) {
    return (delete(
      ticketCommentsTable,
    )..where((t) => t.ticketId.equals(ticketId))).go();
  }
}
