import 'package:drift/drift.dart';

@DataClassName('TicketCommentData')
class TicketCommentsTable extends Table {
  @override
  String get tableName => 'ticket_comments';

  TextColumn get id => text()();
  TextColumn get ticketId => text().named('ticket_id')();
  TextColumn get content => text()();
  TextColumn get authorType => text().named('author_type')();
  TextColumn get aiModel => text().named('ai_model').nullable()();
  IntColumn get createdAt => integer().named('created_at')();

  @override
  Set<Column> get primaryKey => {id};
}
