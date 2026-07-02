// data/models/ticket_comment_model.dart — Drift table definition for ticket_comments (data layer).

import 'package:drift/drift.dart';

/// Drift table backing [TicketComment](../../domain/entities/ticket_comment.dart).
/// Row type is generated as `TicketCommentData`. Append-only by design — no
/// `updated_at` column, and no UPDATE/DELETE is ever issued against it.
@DataClassName('TicketCommentData')
class TicketCommentsTable extends Table {
  @override
  String get tableName => 'ticket_comments';

  /// UUID v4 primary key.
  TextColumn get id => text()();

  /// UUID of the ticket this comment belongs to.
  TextColumn get ticketId => text().named('ticket_id')();

  /// Plain-text comment body.
  TextColumn get content => text()();

  /// `CommentAuthorType.name` string (`'human'` or `'ai'`).
  TextColumn get authorType => text().named('author_type')();

  /// Set only when [authorType] is `'ai'`.
  TextColumn get aiModel => text().named('ai_model').nullable()();

  /// Unix milliseconds.
  IntColumn get createdAt => integer().named('created_at')();

  @override
  Set<Column> get primaryKey => {id};
}
