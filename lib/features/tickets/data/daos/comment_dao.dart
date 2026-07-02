import 'package:drift/drift.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/data/models/ticket_comment_model.dart';

part 'comment_dao.g.dart';

@DriftAccessor(tables: [TicketCommentsTable])
class CommentDao extends DatabaseAccessor<AppDatabase> with _$CommentDaoMixin {
  CommentDao(super.db);

  Future<List<TicketCommentData>> getCommentsForTicket(String ticketId) {
    return (select(ticketCommentsTable)
          ..where((t) => t.ticketId.equals(ticketId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<void> insertComment(TicketCommentsTableCompanion entry) {
    return into(ticketCommentsTable).insert(entry);
  }
}
