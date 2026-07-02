// data/daos/comment_dao.dart — CommentDao Drift accessor (data layer).

import 'package:drift/drift.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/data/models/ticket_comment_model.dart';

part 'comment_dao.g.dart';

/// Drift accessor for [TicketCommentsTable]. No UPDATE or DELETE methods are
/// exposed — append-only by construction.
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
}
