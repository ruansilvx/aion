import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/data/repositories/drift_comment_repository.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';

void main() {
  late AppDatabase database;
  late DriftCommentRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftCommentRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  TicketComment buildComment({
    String id = '',
    String ticketId = 'ticket-1',
    String content = 'A comment',
    CommentAuthorType authorType = CommentAuthorType.human,
    String? aiModel,
    DateTime? createdAt,
  }) {
    return TicketComment(
      id: id,
      ticketId: ticketId,
      content: content,
      authorType: authorType,
      aiModel: aiModel,
      createdAt: createdAt ?? DateTime(2026, 1, 1),
    );
  }

  test('addComment then getCommentsForTicket returns the comment', () async {
    await repository.addComment(buildComment(content: 'Hello'));
    final comments = await repository.getCommentsForTicket('ticket-1');

    expect(comments, hasLength(1));
    expect(comments.first.content, 'Hello');
  });

  test('multiple comments returned in createdAt ascending order', () async {
    await repository.addComment(
      buildComment(content: 'Second', createdAt: DateTime(2026, 1, 2)),
    );
    await repository.addComment(
      buildComment(content: 'First', createdAt: DateTime(2026, 1, 1)),
    );

    final comments = await repository.getCommentsForTicket('ticket-1');

    expect(comments.map((c) => c.content).toList(), ['First', 'Second']);
  });

  test('authorType round-trip: human and ai survive write/read', () async {
    await repository.addComment(
      buildComment(authorType: CommentAuthorType.human),
    );
    await repository.addComment(
      buildComment(
        authorType: CommentAuthorType.ai,
        aiModel: 'claude-sonnet-5',
        createdAt: DateTime(2026, 1, 2),
      ),
    );

    final comments = await repository.getCommentsForTicket('ticket-1');

    expect(comments[0].authorType, CommentAuthorType.human);
    expect(comments[1].authorType, CommentAuthorType.ai);
  });

  test(
    'aiModel field: null for human, non-null for ai, both survive write/read',
    () async {
      await repository.addComment(
        buildComment(authorType: CommentAuthorType.human),
      );
      await repository.addComment(
        buildComment(
          authorType: CommentAuthorType.ai,
          aiModel: 'claude-sonnet-5',
          createdAt: DateTime(2026, 1, 2),
        ),
      );

      final comments = await repository.getCommentsForTicket('ticket-1');

      expect(comments[0].aiModel, isNull);
      expect(comments[1].aiModel, 'claude-sonnet-5');
    },
  );

  test(
    'human and AI comments on the same ticket are both returned together',
    () async {
      await repository.addComment(
        buildComment(authorType: CommentAuthorType.human),
      );
      await repository.addComment(
        buildComment(
          authorType: CommentAuthorType.ai,
          createdAt: DateTime(2026, 1, 2),
        ),
      );

      final comments = await repository.getCommentsForTicket('ticket-1');

      expect(comments, hasLength(2));
    },
  );
}
