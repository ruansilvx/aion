import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/tickets/data/repositories/drift_comment_repository.dart'
    show DriftCommentRepository;
import 'package:aion/features/tickets/data/repositories/drift_ticket_link_repository.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_repository.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_direction.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_field.dart';
import 'package:aion/features/tickets/tickets.dart';

/// The pre-existing default ordering (`createdAt` descending) — passed
/// explicitly to every `searchTickets` call in this file that isn't
/// itself testing the new sort-control behavior (see
/// `aion-arch/changes/ticket-sort-control-and-board-as-default-view`),
/// so those calls keep exercising exactly the ordering they did before
/// `sort` became a required parameter.
const _defaultSort = TicketListSort(
  field: TicketSortField.createdAt,
  direction: TicketSortDirection.descending,
);

/// The pre-existing implicit relevance ordering used whenever a search
/// query was active, before `sort` became a required parameter — passed
/// explicitly to this file's query-driven `searchTickets` calls that
/// assert on match-ranked order.
const _relevanceSort = TicketListSort(
  field: TicketSortField.relevance,
  direction: TicketSortDirection.descending,
);

/// Dummy project [AppDatabase] now requires per-project addressing —
/// unused here since every test passes an explicit in-memory executor.
final _testProject = Project(
  id: 'test-project',
  name: 'Test Project',
  storageKey: 'test-project',
  baselineVersion: '0.1.0',
  createdAt: DateTime(2024, 1, 1),
  lastOpenedAt: DateTime(2024, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late DriftTicketRepository repository;

  Ticket buildTicket({
    String id = '1',
    String title = 'Test ticket',
    TicketPriority priority = TicketPriority.none,
    int? estimate,
    int? timeSpent,
    String? parentId,
  }) {
    final now = DateTime(2026, 1, 1);
    return Ticket(
      id: id,
      ticketId: '',
      type: TicketType.task,
      title: title,
      status: TicketStatus.backlog,
      priority: priority,
      estimate: estimate,
      timeSpent: timeSpent,
      parentId: parentId,
      createdAt: now,
      updatedAt: now,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase(_testProject, NativeDatabase.memory());
    repository = DriftTicketRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Ticket buildSearchable({
    required String id,
    required String title,
    String? description,
    TicketType type = TicketType.task,
    TicketStatus status = TicketStatus.backlog,
    TicketPriority priority = TicketPriority.none,
  }) {
    final now = DateTime(2026, 1, 1);
    return Ticket(
      id: id,
      ticketId: '',
      type: type,
      title: title,
      description: description,
      status: status,
      priority: priority,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('createTicket then getAllTickets returns the created ticket', () async {
    await repository.createTicket(buildTicket());
    final tickets = await repository.getAllTickets();

    expect(tickets, hasLength(1));
    expect(tickets.first.title, 'Test ticket');
  });

  test('importTicket persists the caller-supplied ticketId verbatim', () async {
    final now = DateTime(2026, 1, 1);
    await repository.importTicket(
      Ticket(
        id: 'imported-1',
        ticketId: 'AIO-99',
        type: TicketType.task,
        title: 'Imported ticket',
        status: TicketStatus.backlog,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final tickets = await repository.getAllTickets();

    expect(tickets, hasLength(1));
    expect(tickets.first.ticketId, 'AIO-99');
  });

  test('getTicketById returns correct ticket when found', () async {
    await repository.createTicket(buildTicket(id: 'abc'));
    final found = await repository.getTicketById('abc');

    expect(found, isNotNull);
    expect(found!.id, 'abc');
  });

  test('getTicketById returns null when not found', () async {
    final found = await repository.getTicketById('missing');
    expect(found, isNull);
  });

  test(
    'enum round-trip: type, status, and priority survive write/read',
    () async {
      final now = DateTime(2026, 1, 1);
      final ticket = Ticket(
        id: '1',
        ticketId: '',
        type: TicketType.epic,
        title: 'Epic ticket',
        status: TicketStatus.inReview,
        priority: TicketPriority.critical,
        createdAt: now,
        updatedAt: now,
      );

      await repository.createTicket(ticket);
      final tickets = await repository.getAllTickets();

      expect(tickets.first.type, TicketType.epic);
      expect(tickets.first.status, TicketStatus.inReview);
      expect(tickets.first.priority, TicketPriority.critical);
    },
  );

  test('priority defaults to TicketPriority.none when not supplied', () async {
    await repository.createTicket(buildTicket());
    final tickets = await repository.getAllTickets();

    expect(tickets.first.priority, TicketPriority.none);
  });

  test('estimate and time_spent nullable fields survive write/read', () async {
    await repository.createTicket(
      buildTicket(id: '1', estimate: null, timeSpent: null),
    );
    await repository.createTicket(
      buildTicket(id: '2', estimate: 30, timeSpent: 15),
    );

    final tickets = await repository.getAllTickets();
    final withNulls = tickets.firstWhere((t) => t.id == '1');
    final withValues = tickets.firstWhere((t) => t.id == '2');

    expect(withNulls.estimate, isNull);
    expect(withNulls.timeSpent, isNull);
    expect(withValues.estimate, 30);
    expect(withValues.timeSpent, 15);
  });

  test('bug fields (severity/stepsToReproduce/expectedBehavior/'
      'actualBehavior) survive createTicket write/read', () async {
    final now = DateTime(2026, 1, 1);
    final bug = Ticket(
      id: 'bug-1',
      ticketId: '',
      type: TicketType.bug,
      title: 'Login button unresponsive on Safari',
      status: TicketStatus.backlog,
      severity: TicketSeverity.critical,
      stepsToReproduce: '1. Open Safari\n2. Click login',
      expectedBehavior: 'The login modal opens',
      actualBehavior: 'Nothing happens',
      createdAt: now,
      updatedAt: now,
    );

    await repository.createTicket(bug);
    final found = await repository.getTicketById('bug-1');

    expect(found!.severity, TicketSeverity.critical);
    expect(found.stepsToReproduce, '1. Open Safari\n2. Click login');
    expect(found.expectedBehavior, 'The login modal opens');
    expect(found.actualBehavior, 'Nothing happens');
  });

  test('bug fields default to null for a Task, and null bug fields survive '
      'write/read for a Bug', () async {
    await repository.createTicket(buildTicket(id: 'task-1'));
    final task = await repository.getTicketById('task-1');

    expect(task!.severity, isNull);
    expect(task.stepsToReproduce, isNull);
    expect(task.expectedBehavior, isNull);
    expect(task.actualBehavior, isNull);
  });

  test('updateTicket persists changes to severity/stepsToReproduce/'
      'expectedBehavior/actualBehavior', () async {
    final now = DateTime(2026, 1, 1);
    final bug = Ticket(
      id: 'bug-2',
      ticketId: '',
      type: TicketType.bug,
      title: 'Bug to update',
      status: TicketStatus.backlog,
      createdAt: now,
      updatedAt: now,
    );
    await repository.createTicket(bug);
    final persisted = await repository.getTicketById('bug-2');

    await repository.updateTicket(
      persisted!.copyWith(
        severity: () => TicketSeverity.low,
        stepsToReproduce: () => 'steps',
        expectedBehavior: () => 'expected',
        actualBehavior: () => 'actual',
      ),
    );
    final updated = await repository.getTicketById('bug-2');

    expect(updated!.severity, TicketSeverity.low);
    expect(updated.stepsToReproduce, 'steps');
    expect(updated.expectedBehavior, 'expected');
    expect(updated.actualBehavior, 'actual');
  });

  test('suggestedType and inboxPurpose survive createTicket write/read, '
      'null and populated', () async {
    final now = DateTime(2026, 1, 1);
    await repository.createTicket(
      Ticket(
        id: 'plain',
        ticketId: '',
        type: TicketType.task,
        title: 'No inbox fields',
        status: TicketStatus.backlog,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.createTicket(
      Ticket(
        id: 'idea-1',
        ticketId: '',
        type: TicketType.idea,
        title: 'Brain-dumped idea',
        status: TicketStatus.backlog,
        suggestedType: TicketType.epic,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.createTicket(
      Ticket(
        id: 'chat-1',
        ticketId: '',
        type: TicketType.chat,
        title: 'Inbox chat',
        status: TicketStatus.backlog,
        inboxPurpose: InboxPurpose.brainDump,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final plain = await repository.getTicketById('plain');
    final idea = await repository.getTicketById('idea-1');
    final chat = await repository.getTicketById('chat-1');

    expect(plain!.suggestedType, isNull);
    expect(plain.inboxPurpose, isNull);
    expect(idea!.suggestedType, TicketType.epic);
    expect(idea.inboxPurpose, isNull);
    expect(chat!.inboxPurpose, InboxPurpose.brainDump);
    expect(chat.suggestedType, isNull);
  });

  test(
    'updateTicket persists changes to suggestedType and inboxPurpose',
    () async {
      final now = DateTime(2026, 1, 1);
      await repository.createTicket(
        Ticket(
          id: 'idea-2',
          ticketId: '',
          type: TicketType.idea,
          title: 'Idea to update',
          status: TicketStatus.backlog,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final persisted = await repository.getTicketById('idea-2');

      await repository.updateTicket(
        persisted!.copyWith(
          suggestedType: () => TicketType.bug,
          inboxPurpose: () => InboxPurpose.brainDump,
        ),
      );
      final updated = await repository.getTicketById('idea-2');

      expect(updated!.suggestedType, TicketType.bug);
      expect(updated.inboxPurpose, InboxPurpose.brainDump);
    },
  );

  test('first ticket generated ticketId is "AIO-1" (default prefix)', () async {
    await repository.createTicket(buildTicket());
    final tickets = await repository.getAllTickets();

    expect(tickets.first.ticketId, 'AIO-1');
  });

  test(
    'second ticket generated ticketId is "AIO-2" (sequence increments)',
    () async {
      await repository.createTicket(buildTicket(id: '1'));
      await repository.createTicket(buildTicket(id: '2'));

      final tickets = await repository.getAllTickets();
      final ticketIds = tickets.map((t) => t.ticketId).toSet();

      expect(ticketIds, containsAll(['AIO-1', 'AIO-2']));
    },
  );

  test('ticketId field survives entity mapping round-trip', () async {
    await repository.createTicket(buildTicket(id: 'xyz'));
    final found = await repository.getTicketById('xyz');

    expect(found!.ticketId, 'AIO-1');
  });

  test('updateTicketStatus changes the stored status column', () async {
    await repository.createTicket(buildTicket(id: '1'));
    await repository.updateTicketStatus('1', TicketStatus.done);

    final found = await repository.getTicketById('1');
    expect(found!.status, TicketStatus.done);
  });

  test('updateTicketStatus does not change other fields', () async {
    await repository.createTicket(
      buildTicket(
        id: '1',
        title: 'Unchanged title',
        priority: TicketPriority.high,
      ),
    );
    await repository.updateTicketStatus('1', TicketStatus.done);

    final found = await repository.getTicketById('1');
    expect(found!.title, 'Unchanged title');
    expect(found.priority, TicketPriority.high);
    expect(found.type, TicketType.task);
    expect(found.parentId, isNull);
  });

  test(
    'updateTicketStatus sets updatedAt to a timestamp at or after the original',
    () async {
      await repository.createTicket(buildTicket(id: '1'));
      final before = (await repository.getTicketById('1'))!.updatedAt;

      await repository.updateTicketStatus('1', TicketStatus.done);
      final after = (await repository.getTicketById('1'))!.updatedAt;

      expect(after.isAtSameMomentAs(before) || after.isAfter(before), isTrue);
    },
  );

  test(
    'updateTicket persists title, description, priority, type, estimate, and timeSpent',
    () async {
      await repository.createTicket(buildTicket(id: '1'));
      final original = (await repository.getTicketById('1'))!;

      await repository.updateTicket(
        original.copyWith(
          title: 'Updated title',
          description: () => 'Updated description',
          priority: TicketPriority.high,
          type: TicketType.story,
          estimate: () => 90,
          timeSpent: () => 45,
        ),
      );

      final found = await repository.getTicketById('1');
      expect(found!.title, 'Updated title');
      expect(found.description, 'Updated description');
      expect(found.priority, TicketPriority.high);
      expect(found.type, TicketType.story);
      expect(found.estimate, 90);
      expect(found.timeSpent, 45);
    },
  );

  test(
    'updateTicket leaves status, parentId, embedding, and createdAt untouched',
    () async {
      await repository.createTicket(buildTicket(id: '1'));
      final original = (await repository.getTicketById('1'))!;

      await repository.updateTicket(original.copyWith(title: 'Changed title'));

      final found = await repository.getTicketById('1');
      expect(found!.status, original.status);
      expect(found.parentId, original.parentId);
      expect(found.embedding, original.embedding);
      expect(found.createdAt, original.createdAt);
    },
  );

  test(
    'updateTicket sets updatedAt to a timestamp at or after the original',
    () async {
      await repository.createTicket(buildTicket(id: '1'));
      final before = (await repository.getTicketById('1'))!.updatedAt;

      await repository.updateTicket(
        (await repository.getTicketById('1'))!.copyWith(title: 'New'),
      );
      final after = (await repository.getTicketById('1'))!.updatedAt;

      expect(after.isAtSameMomentAs(before) || after.isAfter(before), isTrue);
    },
  );

  test(
    'updateTicket can explicitly clear estimate, timeSpent, and description to null',
    () async {
      await repository.createTicket(
        buildTicket(id: '1', estimate: 60, timeSpent: 30),
      );
      final original = (await repository.getTicketById('1'))!;

      await repository.updateTicket(
        original.copyWith(
          description: () => null,
          estimate: () => null,
          timeSpent: () => null,
        ),
      );

      final found = await repository.getTicketById('1');
      expect(found!.description, isNull);
      expect(found.estimate, isNull);
      expect(found.timeSpent, isNull);
    },
  );

  test('updateTicketParent changes the stored parent_id column', () async {
    await repository.createTicket(buildTicket(id: '1'));
    await repository.createTicket(buildTicket(id: '2'));
    await repository.updateTicketParent('1', '2');

    final found = await repository.getTicketById('1');
    expect(found!.parentId, '2');
  });

  test('updateTicketParent can clear parentId to null', () async {
    await repository.createTicket(buildTicket(id: '1'));
    await repository.createTicket(buildTicket(id: '2', parentId: '1'));
    await repository.updateTicketParent('2', null);

    final found = await repository.getTicketById('2');
    expect(found!.parentId, isNull);
  });

  test('updateTicketParent does not change other fields', () async {
    await repository.createTicket(
      buildTicket(
        id: '1',
        title: 'Unchanged title',
        priority: TicketPriority.high,
      ),
    );
    await repository.createTicket(buildTicket(id: '2'));
    await repository.updateTicketParent('1', '2');

    final found = await repository.getTicketById('1');
    expect(found!.title, 'Unchanged title');
    expect(found.priority, TicketPriority.high);
    expect(found.status, TicketStatus.backlog);
    expect(found.type, TicketType.task);
  });

  test(
    'updateTicketParent sets updatedAt to a timestamp at or after the original',
    () async {
      await repository.createTicket(buildTicket(id: '1'));
      await repository.createTicket(buildTicket(id: '2'));
      final before = (await repository.getTicketById('1'))!.updatedAt;

      await repository.updateTicketParent('1', '2');
      final after = (await repository.getTicketById('1'))!.updatedAt;

      expect(after.isAtSameMomentAs(before) || after.isAfter(before), isTrue);
    },
  );

  group('updateRollup', () {
    test(
      'writes only estimateRollup/timeSpentRollup, leaving every other '
      'field unchanged',
      () async {
        await repository.createTicket(
          buildTicket(
            id: '1',
            title: 'Unchanged title',
            priority: TicketPriority.high,
          ),
        );

        await repository.updateRollup(
          '1',
          estimateRollup: 45,
          timeSpentRollup: 20,
        );

        final found = await repository.getTicketById('1');
        expect(found!.estimateRollup, 45);
        expect(found.timeSpentRollup, 20);
        expect(found.title, 'Unchanged title');
        expect(found.priority, TicketPriority.high);
        expect(found.status, TicketStatus.backlog);
        expect(found.type, TicketType.task);
      },
    );

    test('can clear both fields back to null', () async {
      await repository.createTicket(buildTicket(id: '1'));
      await repository.updateRollup('1', estimateRollup: 10, timeSpentRollup: 5);

      await repository.updateRollup(
        '1',
        estimateRollup: null,
        timeSpentRollup: null,
      );

      final found = await repository.getTicketById('1');
      expect(found!.estimateRollup, isNull);
      expect(found.timeSpentRollup, isNull);
    });

    test('leaves updatedAt untouched, unlike updateTicket/updateTicketParent', () async {
      await repository.createTicket(buildTicket(id: '1'));
      final before = (await repository.getTicketById('1'))!.updatedAt;

      await repository.updateRollup('1', estimateRollup: 10, timeSpentRollup: null);
      final after = (await repository.getTicketById('1'))!.updatedAt;

      expect(after, before);
    });
  });

  group('trashTicket / trashTickets', () {
    test(
      'moves a childless ticket into trash (deletedAt set, row intact)',
      () async {
        await repository.createTicket(buildTicket(id: '1'));
        await repository.trashTicket('1');

        // Excluded from the live surface...
        expect(await repository.getAllTickets(), isEmpty);
        // ...but the row itself, and its data, are untouched.
        expect(await repository.getTrashedTickets(), hasLength(1));
      },
    );

    test(
      'trashing a grandparent cascades to trash its full multi-level subtree',
      () async {
        await repository.createTicket(buildTicket(id: 'grandparent'));
        await repository.createTicket(
          buildTicket(id: 'parent', parentId: 'grandparent'),
        );
        await repository.createTicket(
          buildTicket(id: 'child', parentId: 'parent'),
        );
        await repository.createTicket(buildTicket(id: 'unrelated'));

        await repository.trashTicket('grandparent');

        final trashedIds = (await repository.getTrashedTickets())
            .map((t) => t.id)
            .toSet();
        expect(trashedIds, {'grandparent', 'parent', 'child'});
        expect((await repository.getAllTickets()).map((t) => t.id), [
          'unrelated',
        ]);
      },
    );

    test('throws StateError when the ticket does not exist', () async {
      await expectLater(
        () => repository.trashTicket('missing'),
        throwsA(isA<StateError>()),
      );
    });

    test('trashTickets returns the total moved (selection + cascaded '
        'descendants), and silently skips a non-existent id', () async {
      await repository.createTicket(buildTicket(id: 'parent'));
      await repository.createTicket(
        buildTicket(id: 'child', parentId: 'parent'),
      );
      await repository.createTicket(buildTicket(id: 'other'));

      final total = await repository.trashTickets([
        'parent',
        'other',
        'missing',
      ]);

      expect(total, 3); // parent + child (cascaded) + other
      expect(await repository.getAllTickets(), isEmpty);
    });
  });

  group('previewTrashCount', () {
    test(
      'matches the count trashTickets actually moves for a simple subtree',
      () async {
        await repository.createTicket(buildTicket(id: 'parent'));
        await repository.createTicket(
          buildTicket(id: 'child', parentId: 'parent'),
        );
        await repository.createTicket(buildTicket(id: 'unrelated'));

        final preview = await repository.previewTrashCount(['parent']);
        expect(preview, 2); // parent + child

        final actual = await repository.trashTickets(['parent']);
        expect(actual, preview);
      },
    );

    test('performs no writes — tickets stay live after a preview', () async {
      await repository.createTicket(buildTicket(id: '1'));

      await repository.previewTrashCount(['1']);

      expect(await repository.getAllTickets(), hasLength(1));
      expect(await repository.getTrashedTickets(), isEmpty);
    });

    test('counts a descendant that is already trashed, matching what '
        'trashTickets would actually move — a live-tickets-only descendant '
        'walk would undercount this case', () async {
      await repository.createTicket(buildTicket(id: 'parent'));
      await repository.createTicket(
        buildTicket(id: 'child', parentId: 'parent'),
      );
      await repository.createTicket(
        buildTicket(id: 'grandchild', parentId: 'child'),
      );
      // Trash the child (and its own subtree) individually first,
      // leaving the parent live.
      await repository.trashTicket('child');
      expect(await repository.getAllTickets(), hasLength(1)); // parent

      final preview = await repository.previewTrashCount(['parent']);
      final actual = await repository.trashTickets(['parent']);

      expect(preview, 3); // parent + already-trashed child + grandchild
      expect(actual, preview);
    });
  });

  group('restoreTicket', () {
    test('restoring a deep child also restores its trashed ancestors, '
        'leaving unrelated trashed tickets untouched', () async {
      await repository.createTicket(buildTicket(id: 'grandparent'));
      await repository.createTicket(
        buildTicket(id: 'parent', parentId: 'grandparent'),
      );
      await repository.createTicket(
        buildTicket(id: 'child', parentId: 'parent'),
      );
      await repository.createTicket(buildTicket(id: 'unrelated-trashed'));
      await repository.trashTicket('grandparent');
      await repository.trashTicket('unrelated-trashed');

      await repository.restoreTicket('child');

      final liveIds = (await repository.getAllTickets())
          .map((t) => t.id)
          .toSet();
      expect(liveIds, {'grandparent', 'parent', 'child'});
      expect((await repository.getTrashedTickets()).map((t) => t.id), [
        'unrelated-trashed',
      ]);
    });

    test('throws StateError when the ticket does not exist', () async {
      await expectLater(
        () => repository.restoreTicket('missing'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('permanentlyDeleteTicket / emptyTrash', () {
    test(
      'permanently deletes a ticket, its subtree, comments, and links',
      () async {
        await repository.createTicket(buildTicket(id: 'parent'));
        await repository.createTicket(
          buildTicket(id: 'child', parentId: 'parent'),
        );
        await repository.createTicket(buildTicket(id: 'other'));

        final commentRepository = DriftCommentRepository(database);
        await commentRepository.addComment(
          TicketComment(
            id: '',
            ticketId: 'parent',
            content: 'A comment',
            authorType: CommentAuthorType.human,
            createdAt: DateTime(2026, 1, 1),
          ),
        );
        final linkRepository = DriftTicketLinkRepository(database);
        await linkRepository.createLink(
          sourceTicketId: 'parent',
          targetTicketId: 'other',
          linkType: TicketLinkType.relatesTo,
        );

        await repository.trashTicket('parent');
        await repository.permanentlyDeleteTicket('parent');

        expect(await repository.getTicketById('parent'), isNull);
        expect(await repository.getTicketById('child'), isNull);
        expect(await commentRepository.getCommentsForTicket('parent'), isEmpty);
        expect(await linkRepository.getLinksForTicket('parent'), isEmpty);
        expect(await repository.getTicketById('other'), isNotNull);
      },
    );

    test('throws StateError when the ticket does not exist', () async {
      await expectLater(
        () => repository.permanentlyDeleteTicket('missing'),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'permanentlyDeleteTicket also clears page_wikilinks rows where the '
      'deleted ticket is source or target — '
      'aion-arch/changes/inline-wikilink-backlinks',
      () async {
        await repository.createTicket(
          buildSearchable(
            id: 'wiki-source',
            title: 'Wiki Source',
            type: TicketType.page,
          ),
        );
        await repository.createTicket(
          buildSearchable(
            id: 'wiki-target',
            title: 'Wiki Target',
            type: TicketType.page,
          ),
        );
        await database.pageWikilinkDao.replaceOutgoingLinks('wiki-source', {
          'wiki-target',
        });

        await repository.trashTicket('wiki-source');
        await repository.permanentlyDeleteTicket('wiki-source');

        expect(
          await database.pageWikilinkDao.getOutgoingLinks('wiki-source'),
          isEmpty,
        );
        expect(
          await database.pageWikilinkDao.getIncomingLinks('wiki-target'),
          isEmpty,
        );
      },
    );

    test(
      'emptyTrash removes every trashed ticket and only trashed tickets',
      () async {
        await repository.createTicket(buildTicket(id: 'trashed-1'));
        await repository.createTicket(buildTicket(id: 'trashed-2'));
        await repository.createTicket(buildTicket(id: 'live'));
        await repository.trashTicket('trashed-1');
        await repository.trashTicket('trashed-2');

        await repository.emptyTrash();

        expect(await repository.getTrashedTickets(), isEmpty);
        expect(await repository.getTicketById('trashed-1'), isNull);
        expect(await repository.getTicketById('trashed-2'), isNull);
        expect(await repository.getTicketById('live'), isNotNull);
      },
    );

    test('emptyTrash is a no-op when trash is already empty', () async {
      await repository.createTicket(buildTicket(id: 'live'));
      await expectLater(repository.emptyTrash(), completes);
      expect(await repository.getTicketById('live'), isNotNull);
    });
  });

  group('purgeTrashOlderThan', () {
    test('purges only tickets older than the cutoff, leaving younger '
        'trashed tickets and live tickets untouched', () async {
      await repository.createTicket(buildTicket(id: 'old'));
      await repository.createTicket(buildTicket(id: 'young'));
      await repository.createTicket(buildTicket(id: 'live'));
      await repository.trashTicket('old');
      await repository.trashTicket('young');

      final now = DateTime.now();
      await database.ticketDao.softDeleteByIds([
        'old',
      ], now.subtract(const Duration(days: 40)).millisecondsSinceEpoch);
      await database.ticketDao.softDeleteByIds([
        'young',
      ], now.subtract(const Duration(days: 5)).millisecondsSinceEpoch);

      final purged = await repository.purgeTrashOlderThan(
        const Duration(days: 30),
      );

      expect(purged, 1);
      expect(await repository.getTicketById('old'), isNull);
      expect(await repository.getTicketById('young'), isNotNull);
      expect(await repository.getTicketById('live'), isNotNull);
    });

    test('cascades to comments and ticket_links', () async {
      await repository.createTicket(buildTicket(id: 'old'));
      await repository.createTicket(buildTicket(id: 'other'));

      final commentRepository = DriftCommentRepository(database);
      await commentRepository.addComment(
        TicketComment(
          id: '',
          ticketId: 'old',
          content: 'A comment',
          authorType: CommentAuthorType.human,
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      final linkRepository = DriftTicketLinkRepository(database);
      await linkRepository.createLink(
        sourceTicketId: 'old',
        targetTicketId: 'other',
        linkType: TicketLinkType.relatesTo,
      );

      await repository.trashTicket('old');
      await database.ticketDao.softDeleteByIds(
        ['old'],
        DateTime.now()
            .subtract(const Duration(days: 40))
            .millisecondsSinceEpoch,
      );

      final purged = await repository.purgeTrashOlderThan(
        const Duration(days: 30),
      );

      expect(purged, 1);
      expect(await commentRepository.getCommentsForTicket('old'), isEmpty);
      expect(await linkRepository.getLinksForTicket('old'), isEmpty);
    });

    test('is a no-op when nothing qualifies', () async {
      await repository.createTicket(buildTicket(id: 'young'));
      await repository.trashTicket('young');

      final purged = await repository.purgeTrashOlderThan(
        const Duration(days: 30),
      );

      expect(purged, 0);
      expect(await repository.getTicketById('young'), isNotNull);
    });
  });

  group('getLinksForTicket excludes trashed', () {
    late DriftTicketLinkRepository linkRepository;

    setUp(() {
      linkRepository = DriftTicketLinkRepository(database);
    });

    test(
      'a link between two live tickets is counted from both sides',
      () async {
        await repository.createTicket(buildTicket(id: 'a'));
        await repository.createTicket(buildTicket(id: 'b'));
        await linkRepository.createLink(
          sourceTicketId: 'a',
          targetTicketId: 'b',
          linkType: TicketLinkType.relatesTo,
        );

        expect(await linkRepository.getLinksForTicket('a'), hasLength(1));
        expect(await linkRepository.getLinksForTicket('b'), hasLength(1));
      },
    );

    test(
      'a link to a trashed ticket is excluded from the live ticket\'s result',
      () async {
        await repository.createTicket(buildTicket(id: 'a'));
        await repository.createTicket(buildTicket(id: 'b'));
        await linkRepository.createLink(
          sourceTicketId: 'a',
          targetTicketId: 'b',
          linkType: TicketLinkType.relatesTo,
        );

        await repository.trashTicket('b');

        expect(await linkRepository.getLinksForTicket('a'), isEmpty);
      },
    );

    test(
      'restoring the trashed ticket makes the link reappear with no extra write',
      () async {
        await repository.createTicket(buildTicket(id: 'a'));
        await repository.createTicket(buildTicket(id: 'b'));
        await linkRepository.createLink(
          sourceTicketId: 'a',
          targetTicketId: 'b',
          linkType: TicketLinkType.relatesTo,
        );
        await repository.trashTicket('b');
        expect(await linkRepository.getLinksForTicket('a'), isEmpty);

        await repository.restoreTicket('b');

        expect(await linkRepository.getLinksForTicket('a'), hasLength(1));
      },
    );

    test('a ticket with no links returns an empty list', () async {
      await repository.createTicket(buildTicket(id: 'a'));

      expect(await linkRepository.getLinksForTicket('a'), isEmpty);
    });

    test(
      'a ticket linked as both source and target has both returned',
      () async {
        await repository.createTicket(buildTicket(id: 'a'));
        await repository.createTicket(buildTicket(id: 'b'));
        await repository.createTicket(buildTicket(id: 'c'));
        await linkRepository.createLink(
          sourceTicketId: 'a',
          targetTicketId: 'b',
          linkType: TicketLinkType.relatesTo,
        );
        await linkRepository.createLink(
          sourceTicketId: 'c',
          targetTicketId: 'a',
          linkType: TicketLinkType.relatesTo,
        );

        expect(await linkRepository.getLinksForTicket('a'), hasLength(2));
      },
    );

    test(
      'a self-link (source and target the same ticket) is only counted once',
      () async {
        await repository.createTicket(buildTicket(id: 'a'));
        await linkRepository.createLink(
          sourceTicketId: 'a',
          targetTicketId: 'a',
          linkType: TicketLinkType.relatesTo,
        );

        expect(await linkRepository.getLinksForTicket('a'), hasLength(1));
      },
    );
  });

  group('getLinksByTypes', () {
    late DriftTicketLinkRepository linkRepository;

    setUp(() {
      linkRepository = DriftTicketLinkRepository(database);
    });

    test(
      'returns only rows matching the requested types across multiple tickets',
      () async {
        await repository.createTicket(buildTicket(id: 'a'));
        await repository.createTicket(buildTicket(id: 'b'));
        await repository.createTicket(buildTicket(id: 'c'));
        await linkRepository.createLink(
          sourceTicketId: 'a',
          targetTicketId: 'b',
          linkType: TicketLinkType.blocks,
        );
        await linkRepository.createLink(
          sourceTicketId: 'b',
          targetTicketId: 'c',
          linkType: TicketLinkType.blockedBy,
        );
        await linkRepository.createLink(
          sourceTicketId: 'a',
          targetTicketId: 'c',
          linkType: TicketLinkType.relatesTo,
        );

        final rows = await linkRepository.getLinksByTypes([
          TicketLinkType.blocks,
          TicketLinkType.blockedBy,
        ]);

        expect(rows, hasLength(2));
        expect(
          rows.map((r) => r.linkType),
          containsAll(['blocks', 'blockedBy']),
        );
      },
    );

    test('excludes a row whose other side is trashed', () async {
      await repository.createTicket(buildTicket(id: 'a'));
      await repository.createTicket(buildTicket(id: 'b'));
      await linkRepository.createLink(
        sourceTicketId: 'a',
        targetTicketId: 'b',
        linkType: TicketLinkType.blocks,
      );

      await repository.trashTicket('b');

      expect(
        await linkRepository.getLinksByTypes([TicketLinkType.blocks]),
        isEmpty,
      );
    });

    test('returns [] when no rows match', () async {
      await repository.createTicket(buildTicket(id: 'a'));
      await repository.createTicket(buildTicket(id: 'b'));
      await linkRepository.createLink(
        sourceTicketId: 'a',
        targetTicketId: 'b',
        linkType: TicketLinkType.relatesTo,
      );

      expect(
        await linkRepository.getLinksByTypes([TicketLinkType.blocks]),
        isEmpty,
      );
    });
  });

  group('searchTickets', () {
    test(
      'query matches title/description; a title hit ranks ahead of a description-only hit',
      () async {
        await repository.createTicket(
          buildSearchable(
            id: 'desc-hit',
            title: 'Unrelated title',
            description: 'mentions authentication in passing',
          ),
        );
        await repository.createTicket(
          buildSearchable(id: 'title-hit', title: 'Fix authentication bug'),
        );
        await repository.createTicket(
          buildSearchable(id: 'no-match', title: 'Completely different'),
        );

        final results = await repository.searchTickets(
          query: 'authentication',
          sort: _relevanceSort,
          limit: 100,
        );

        expect(results.tickets.map((t) => t.id), ['title-hit', 'desc-hit']);
      },
    );

    test('status/type/priority filters return only exact matches', () async {
      await repository.createTicket(
        buildSearchable(
          id: 'match',
          title: 'A',
          type: TicketType.story,
          status: TicketStatus.inProgress,
          priority: TicketPriority.high,
        ),
      );
      await repository.createTicket(
        buildSearchable(
          id: 'wrong-type',
          title: 'B',
          type: TicketType.task,
          status: TicketStatus.inProgress,
          priority: TicketPriority.high,
        ),
      );

      final results = await repository.searchTickets(
        types: {TicketType.story},
        statuses: {TicketStatus.inProgress},
        priorities: {TicketPriority.high},
        sort: _defaultSort,
        limit: 100,
      );

      expect(results.tickets.map((t) => t.id), ['match']);
    });

    test('query and a structured filter combine (ANDed)', () async {
      await repository.createTicket(
        buildSearchable(
          id: 'match',
          title: 'Fix login bug',
          type: TicketType.task,
        ),
      );
      await repository.createTicket(
        buildSearchable(
          id: 'wrong-type',
          title: 'Fix login bug',
          type: TicketType.story,
        ),
      );
      await repository.createTicket(
        buildSearchable(
          id: 'wrong-query',
          title: 'Unrelated',
          type: TicketType.task,
        ),
      );

      final results = await repository.searchTickets(
        query: 'login',
        types: {TicketType.task},
        sort: _relevanceSort,
        limit: 100,
      );

      expect(results.tickets.map((t) => t.id), ['match']);
    });

    test(
      'every parameter null/omitted returns everything, parity with getAllTickets',
      () async {
        await repository.createTicket(buildSearchable(id: '1', title: 'A'));
        await repository.createTicket(buildSearchable(id: '2', title: 'B'));

        final all = await repository.getAllTickets();
        final searched = await repository.searchTickets(
          sort: _defaultSort,
          limit: 100,
        );

        expect(
          searched.tickets.map((t) => t.id).toSet(),
          all.map((t) => t.id).toSet(),
        );
      },
    );

    test('a query containing FTS5-special characters does not throw', () async {
      await repository.createTicket(
        buildSearchable(id: '1', title: 'Fix drift-web init bug'),
      );

      await expectLater(
        () => repository.searchTickets(
          query: '-drift-web "quoted"',
          sort: _relevanceSort,
          limit: 100,
        ),
        returnsNormally,
      );
    });

    test(
      'excludes trashed tickets, both unfiltered and with a text query',
      () async {
        await repository.createTicket(
          buildSearchable(id: 'live', title: 'Fix authentication bug'),
        );
        await repository.createTicket(
          buildSearchable(id: 'trashed', title: 'Fix authentication too'),
        );
        await repository.trashTicket('trashed');

        expect(
          (await repository.searchTickets(
            sort: _defaultSort,
            limit: 100,
          )).tickets.map((t) => t.id),
          ['live'],
        );
        expect(
          (await repository.searchTickets(
            query: 'authentication',
            sort: _relevanceSort,
            limit: 100,
          )).tickets.map((t) => t.id),
          ['live'],
        );
      },
    );

    group('pagination (limit/offset -> hasMore)', () {
      test(
        'returns exactly limit tickets with hasMore true when more rows exist',
        () async {
          for (var i = 0; i < 5; i++) {
            await repository.createTicket(
              buildSearchable(id: 'p$i', title: 'Ticket $i'),
            );
          }

          final page = await repository.searchTickets(
            sort: _defaultSort,
            limit: 3,
          );

          expect(page.tickets.length, 3);
          expect(page.hasMore, isTrue);
        },
      );

      test('hasMore is false when the DAO returns <= limit rows', () async {
        for (var i = 0; i < 3; i++) {
          await repository.createTicket(
            buildSearchable(id: 'p$i', title: 'Ticket $i'),
          );
        }

        final page = await repository.searchTickets(
          sort: _defaultSort,
          limit: 3,
        );

        expect(page.tickets.length, 3);
        expect(page.hasMore, isFalse);
      });

      test('offset skips already-loaded rows on the next page', () async {
        for (var i = 0; i < 5; i++) {
          await repository.createTicket(
            buildSearchable(id: 'p$i', title: 'Ticket $i'),
          );
        }

        final firstPage = await repository.searchTickets(
          sort: _defaultSort,
          limit: 3,
        );
        final secondPage = await repository.searchTickets(
          sort: _defaultSort,
          limit: 3,
          offset: firstPage.tickets.length,
        );

        expect(
          firstPage.tickets
              .map((t) => t.id)
              .toSet()
              .intersection(secondPage.tickets.map((t) => t.id).toSet()),
          isEmpty,
        );
        expect(secondPage.tickets.length, 2);
        expect(secondPage.hasMore, isFalse);
      });
    });
  });

  group('schema migration (v1 -> current)', () {
    test(
      'onUpgrade backfills existing rows into the FTS5 search index',
      () async {
        // In-memory SQLite doesn't persist across separate connections, so
        // this test needs a real file to genuinely close and reopen
        // against — exactly the scenario onUpgrade exists for (an
        // existing local database on disk).
        final tempDir = Directory.systemTemp.createTempSync(
          'aion_migration_test',
        );
        final dbFile = File('${tempDir.path}/test.sqlite');
        addTearDown(() => tempDir.deleteSync(recursive: true));

        // A fresh AppDatabase always runs onCreate at the *current*
        // schemaVersion (10), which already includes the search
        // infrastructure, the `deleted_at` column, the `sync_status`
        // column, the `complexity`/`sdd_stage` columns, the
        // `severity`/`steps_to_reproduce`/`expected_behavior`/
        // `actual_behavior` columns, `ticket_comments`'
        // `input_tokens`/`output_tokens` columns, the
        // `suggested_type`/`inbox_purpose` columns, `estimate_rollup`/
        // `time_spent_rollup`, and `complexity_source`/`estimate_source`
        // — so the v1 shape has to be built by hand: strip back down to
        // just the bare tables, insert data, then stamp user_version back
        // to 1.
        final v1Db = AppDatabase(_testProject, NativeDatabase(dbFile));
        await v1Db.customStatement('DROP TABLE IF EXISTS tickets_fts;');
        await v1Db.customStatement('DROP TRIGGER IF EXISTS tickets_fts_ai;');
        await v1Db.customStatement('DROP TRIGGER IF EXISTS tickets_fts_ad;');
        await v1Db.customStatement('DROP TRIGGER IF EXISTS tickets_fts_au;');
        await v1Db.customStatement('DROP INDEX IF EXISTS idx_tickets_status;');
        await v1Db.customStatement('DROP INDEX IF EXISTS idx_tickets_type;');
        await v1Db.customStatement(
          'DROP INDEX IF EXISTS idx_tickets_priority;',
        );
        await v1Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN deleted_at;',
        );
        await v1Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN sdd_stage;',
        );

        // sync_status/complexity/severity/steps_to_reproduce/
        // expected_behavior/actual_behavior/suggested_type/inbox_purpose
        // can't be dropped yet — createTicket's generated companion sets
        // all of them explicitly (unlike deleted_at/sdd_stage, which it
        // never touches), so they must still exist for this insert to
        // succeed. Drop them immediately after, before stamping
        // user_version, to finish simulating the pre-v4 shape.
        final preMigrationRepo = DriftTicketRepository(v1Db);
        await preMigrationRepo.createTicket(
          buildSearchable(id: 'pre-existing', title: 'Fix authentication bug'),
        );
        await v1Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN sync_status;',
        );
        await v1Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN complexity;',
        );
        await v1Db.customStatement('ALTER TABLE tickets DROP COLUMN severity;');
        await v1Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN steps_to_reproduce;',
        );
        await v1Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN expected_behavior;',
        );
        await v1Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN actual_behavior;',
        );
        await v1Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN suggested_type;',
        );
        await v1Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN inbox_purpose;',
        );
        // estimate_rollup/time_spent_rollup (v9) — same reasoning: never
        // touched by createTicket's companion, so no insert-ordering
        // constraint, but createAll() already created them and onUpgrade's
        // `from < 9` addColumn step would otherwise fail with "duplicate
        // column name" against a column that already exists.
        await v1Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN estimate_rollup;',
        );
        await v1Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN time_spent_rollup;',
        );
        // complexity_source/estimate_source (v10) can't be dropped until
        // after the insert above either — createTicket's companion sets
        // them explicitly (mirroring complexity/severity/etc. above).
        await v1Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN complexity_source;',
        );
        await v1Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN estimate_source;',
        );
        // ticket_comments' input_tokens/output_tokens (v7) — dropped even
        // though this test's assertions never touch that table, since
        // onUpgrade's `from < 7` addColumn step still runs unconditionally
        // and would otherwise fail with "duplicate column name" against a
        // column createAll() already created.
        await v1Db.customStatement(
          'ALTER TABLE ticket_comments DROP COLUMN input_tokens;',
        );
        await v1Db.customStatement(
          'ALTER TABLE ticket_comments DROP COLUMN output_tokens;',
        );
        // predicted_execution_tokens_low/high (v14) — same reasoning as
        // estimate_rollup/time_spent_rollup above.
        await v1Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN predicted_execution_tokens_low;',
        );
        await v1Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN predicted_execution_tokens_high;',
        );
        await v1Db.customStatement('PRAGMA user_version = 1;');
        await v1Db.close();

        // Reopen against the same file at the current schemaVersion (10).
        // Drift reads user_version=1, sees schemaVersion=10, and runs
        // onUpgrade automatically (the v2 through v10 steps).
        final v2Db = AppDatabase(_testProject, NativeDatabase(dbFile));
        final upgradedRepo = DriftTicketRepository(v2Db);

        final results = await upgradedRepo.searchTickets(
          query: 'authentication',
          sort: _relevanceSort,
          limit: 100,
        );

        expect(results.tickets.map((t) => t.id), ['pre-existing']);
        // The v3 step ran too — the pre-existing ticket is live, not
        // trashed, since it existed before trash was ever a concept.
        expect(await upgradedRepo.getTrashedTickets(), isEmpty);
        await v2Db.close();
      },
    );

    test('onUpgrade from v7 adds suggested_type/inbox_purpose, defaulting to '
        'null on existing rows', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'aion_migration_v8_test',
      );
      final dbFile = File('${tempDir.path}/test.sqlite');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final v7Db = AppDatabase(_testProject, NativeDatabase(dbFile));
      final preMigrationRepo = DriftTicketRepository(v7Db);
      await preMigrationRepo.createTicket(
        buildSearchable(id: 'pre-existing', title: 'Pre-v8 ticket'),
      );
      // suggested_type/inbox_purpose can't be dropped until after the
      // insert above, since createTicket's companion sets them
      // explicitly — same reasoning as the v1 simulation above.
      await v7Db.customStatement(
        'ALTER TABLE tickets DROP COLUMN suggested_type;',
      );
      await v7Db.customStatement(
        'ALTER TABLE tickets DROP COLUMN inbox_purpose;',
      );
      // estimate_rollup/time_spent_rollup (v9) — same reasoning as the v1
      // simulation above: createAll() already created them, so onUpgrade's
      // `from < 9` addColumn step needs them absent first.
      await v7Db.customStatement(
        'ALTER TABLE tickets DROP COLUMN estimate_rollup;',
      );
      await v7Db.customStatement(
        'ALTER TABLE tickets DROP COLUMN time_spent_rollup;',
      );
      // complexity_source/estimate_source (v10) — createTicket's companion
      // sets them explicitly, so they can't be dropped until after the
      // insert above; createAll() already created them, so onUpgrade's
      // `from < 10` addColumn step needs them absent first too.
      await v7Db.customStatement(
        'ALTER TABLE tickets DROP COLUMN complexity_source;',
      );
      await v7Db.customStatement(
        'ALTER TABLE tickets DROP COLUMN estimate_source;',
      );
      // predicted_execution_tokens_low/high (v14) — same reasoning as
      // complexity_source/estimate_source above.
      await v7Db.customStatement(
        'ALTER TABLE tickets DROP COLUMN predicted_execution_tokens_low;',
      );
      await v7Db.customStatement(
        'ALTER TABLE tickets DROP COLUMN predicted_execution_tokens_high;',
      );
      await v7Db.customStatement('PRAGMA user_version = 7;');
      await v7Db.close();

      final v8Db = AppDatabase(_testProject, NativeDatabase(dbFile));
      final upgradedRepo = DriftTicketRepository(v8Db);

      final found = await upgradedRepo.getTicketById('pre-existing');
      expect(found, isNotNull);
      expect(found!.suggestedType, isNull);
      expect(found.inboxPurpose, isNull);

      await upgradedRepo.updateTicket(
        found.copyWith(suggestedType: () => TicketType.epic),
      );
      final updated = await upgradedRepo.getTicketById('pre-existing');
      expect(updated!.suggestedType, TicketType.epic);

      await v8Db.close();
    });

    test(
      'onUpgrade from v8 backfills estimateRollup/timeSpentRollup for '
      'pre-existing hierarchical data',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'aion_migration_v9_test',
        );
        final dbFile = File('${tempDir.path}/test.sqlite');
        addTearDown(() => tempDir.deleteSync(recursive: true));

        final v8Db = AppDatabase(_testProject, NativeDatabase(dbFile));
        final preMigrationRepo = DriftTicketRepository(v8Db);
        // Epic -> Story -> Task, mirroring the live hierarchy this
        // migration exists to backfill correctly on first open of a
        // pre-existing project — see
        // `aion-arch/changes/estimate-timespent-rollup-for-ticket-hierarchy/design.md`
        // §1.4.
        await preMigrationRepo.createTicket(
          buildTicket(id: 'epic-1', title: 'Pre-v9 Epic'),
        );
        await preMigrationRepo.createTicket(
          buildTicket(
            id: 'story-1',
            title: 'Pre-v9 Story',
            parentId: 'epic-1',
          ),
        );
        await preMigrationRepo.createTicket(
          buildTicket(
            id: 'task-1',
            title: 'Pre-v9 Task',
            parentId: 'story-1',
            estimate: 90,
            timeSpent: 30,
          ),
        );
        // estimate_rollup/time_spent_rollup can't be dropped until after
        // the inserts above — createTicket's companion never sets them
        // (see `DriftTicketRepository._buildInsertCompanion`), so there's
        // no insert-ordering constraint, but createAll() already created
        // them and onUpgrade's `from < 9` addColumn step would otherwise
        // fail with "duplicate column name" against a column that
        // already exists.
        await v8Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN estimate_rollup;',
        );
        await v8Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN time_spent_rollup;',
        );
        // complexity_source/estimate_source (v10) — createTicket's
        // companion sets them explicitly, so they can't be dropped until
        // after the inserts above; createAll() already created them, so
        // onUpgrade's `from < 10` addColumn step needs them absent first
        // too — same reasoning as `estimate_rollup`/`time_spent_rollup`.
        await v8Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN complexity_source;',
        );
        await v8Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN estimate_source;',
        );
        // predicted_execution_tokens_low/high (v14) — same reasoning as
        // complexity_source/estimate_source above.
        await v8Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN predicted_execution_tokens_low;',
        );
        await v8Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN predicted_execution_tokens_high;',
        );
        await v8Db.customStatement('PRAGMA user_version = 8;');
        await v8Db.close();

        // Reopen against the same file at the current schemaVersion (10).
        // Drift reads user_version=8, sees schemaVersion=10, and runs both
        // the `from < 9` onUpgrade step (add estimate_rollup/
        // time_spent_rollup, then `_backfillRollups`) and the `from < 10`
        // step (add complexity_source/estimate_source — no-op backfill
        // here, since none of these pre-existing rows have
        // complexity/estimate set).
        final v9Db = AppDatabase(_testProject, NativeDatabase(dbFile));
        final upgradedRepo = DriftTicketRepository(v9Db);

        final epic = await upgradedRepo.getTicketById('epic-1');
        final story = await upgradedRepo.getTicketById('story-1');
        final task = await upgradedRepo.getTicketById('task-1');

        expect(epic!.estimateRollup, 90);
        expect(epic.timeSpentRollup, 30);
        expect(story!.estimateRollup, 90);
        expect(story.timeSpentRollup, 30);
        // The leaf task itself has no live children — its own rollup
        // stays null, backfill only ever fills internal nodes (see
        // `ticket_rollup_calculator.dart`'s `computeRollups`).
        expect(task!.estimateRollup, isNull);
        expect(task.timeSpentRollup, isNull);

        await v9Db.close();
      },
    );

    test(
      'onUpgrade from v9 backfills complexity_source/estimate_source to '
      "'manual' for already-sized rows, leaving unsized rows null",
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'aion_migration_v10_test',
        );
        final dbFile = File('${tempDir.path}/test.sqlite');
        addTearDown(() => tempDir.deleteSync(recursive: true));

        final v9Db = AppDatabase(_testProject, NativeDatabase(dbFile));
        final preMigrationRepo = DriftTicketRepository(v9Db);
        final now = DateTime(2026, 1, 1);
        // Sized by hand (the only way before this change) — expect a
        // 'manual' backfill.
        await preMigrationRepo.createTicket(
          Ticket(
            id: 'sized',
            ticketId: '',
            type: TicketType.task,
            title: 'Pre-v10 sized ticket',
            status: TicketStatus.backlog,
            complexity: TicketComplexity.medium,
            estimate: 60,
            createdAt: now,
            updatedAt: now,
          ),
        );
        // Never sized — expect both source columns to stay null.
        await preMigrationRepo.createTicket(
          buildTicket(id: 'unsized', title: 'Pre-v10 unsized ticket'),
        );
        // complexity_source/estimate_source can't be dropped until after
        // the inserts above — createTicket's companion sets them
        // explicitly; createAll() already created them, so onUpgrade's
        // `from < 10` addColumn step needs them absent first.
        await v9Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN complexity_source;',
        );
        await v9Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN estimate_source;',
        );
        // predicted_execution_tokens_low/high (v14) — same reasoning as
        // complexity_source/estimate_source above.
        await v9Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN predicted_execution_tokens_low;',
        );
        await v9Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN predicted_execution_tokens_high;',
        );
        await v9Db.customStatement('PRAGMA user_version = 9;');
        await v9Db.close();

        // Reopen against the same file at the current schemaVersion (10).
        // Drift reads user_version=9, sees schemaVersion=10, and runs the
        // `from < 10` onUpgrade step — add the two columns, then backfill
        // 'manual' wherever complexity/estimate is already set.
        final v10Db = AppDatabase(_testProject, NativeDatabase(dbFile));
        final upgradedRepo = DriftTicketRepository(v10Db);

        final sized = await upgradedRepo.getTicketById('sized');
        final unsized = await upgradedRepo.getTicketById('unsized');

        expect(sized!.complexitySource, TicketEstimationSource.manual);
        expect(sized.estimateSource, TicketEstimationSource.manual);
        expect(unsized!.complexitySource, isNull);
        expect(unsized.estimateSource, isNull);

        await v10Db.close();
      },
    );

    test(
      'onUpgrade from v11 backfills page_wikilinks from an existing page\'s '
      'bare-title [[...]] reference — '
      'aion-arch/changes/inline-wikilink-backlinks',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'aion_migration_v12_test',
        );
        final dbFile = File('${tempDir.path}/test.sqlite');
        addTearDown(() => tempDir.deleteSync(recursive: true));

        final v11Db = AppDatabase(_testProject, NativeDatabase(dbFile));
        final preMigrationRepo = DriftTicketRepository(v11Db);
        final now = DateTime(2026, 1, 1);
        await preMigrationRepo.createTicket(
          Ticket(
            id: 'target',
            ticketId: '',
            type: TicketType.page,
            title: 'Target Page',
            description: 'Nothing referencing anything here.',
            status: TicketStatus.backlog,
            createdAt: now,
            updatedAt: now,
          ),
        );
        await preMigrationRepo.createTicket(
          Ticket(
            id: 'source',
            ticketId: '',
            type: TicketType.page,
            title: 'Source Page',
            description: 'See [[Target Page]] for details.',
            status: TicketStatus.backlog,
            createdAt: now,
            updatedAt: now,
          ),
        );
        // `page_wikilinks` doesn't exist pre-v12 — drop it (createAll()
        // already made it at the real current schemaVersion) and roll
        // user_version back to 11, simulating a real pre-v12 database.
        await v11Db.customStatement('DROP TABLE page_wikilinks;');
        // predicted_execution_tokens_low/high (v14) — same reasoning as
        // the other migration-simulation tests in this file: createAll()
        // already created them, so onUpgrade's `from < 14` addColumn step
        // needs them absent first.
        await v11Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN predicted_execution_tokens_low;',
        );
        await v11Db.customStatement(
          'ALTER TABLE tickets DROP COLUMN predicted_execution_tokens_high;',
        );
        await v11Db.customStatement('PRAGMA user_version = 11;');
        await v11Db.close();

        // Reopen against the same file at the current schemaVersion (12).
        // Drift reads user_version=11, sees schemaVersion=12, and runs
        // the `from < 12` onUpgrade step — create the table, then run
        // the one-time computed backfill.
        final v12Db = AppDatabase(_testProject, NativeDatabase(dbFile));
        final rows = await v12Db.pageWikilinkDao.getOutgoingLinks('source');

        expect(rows, hasLength(1));
        expect(rows.single.targetPageId, 'target');

        await v12Db.close();
      },
    );
  });

  group('updateTicket stamps complexitySource/estimateSource', () {
    test('setting complexity/estimate on updateTicket with both *Edited '
        'flags stamps manual', () async {
      await repository.createTicket(buildTicket(id: '1'));
      final persisted = await repository.getTicketById('1');

      await repository.updateTicket(
        persisted!.copyWith(
          complexity: () => TicketComplexity.large,
          estimate: () => 120,
        ),
        complexityEdited: true,
        estimateEdited: true,
      );
      final updated = await repository.getTicketById('1');

      expect(updated!.complexity, TicketComplexity.large);
      expect(updated.complexitySource, TicketEstimationSource.manual);
      expect(updated.estimate, 120);
      expect(updated.estimateSource, TicketEstimationSource.manual);
    });

    test('setting complexity/estimate on updateTicket WITHOUT the *Edited '
        'flags leaves the source columns untouched (null, since neither '
        'was previously sized)', () async {
      await repository.createTicket(buildTicket(id: '1'));
      final persisted = await repository.getTicketById('1');

      await repository.updateTicket(
        persisted!.copyWith(
          complexity: () => TicketComplexity.large,
          estimate: () => 120,
        ),
      );
      final updated = await repository.getTicketById('1');

      // The value is written either way (updateTicket always persists
      // whatever complexity/estimate the passed Ticket carries) — only the
      // *source* stamp is gated by complexityEdited/estimateEdited.
      expect(updated!.complexity, TicketComplexity.large);
      expect(updated.estimate, 120);
      expect(updated.complexitySource, isNull);
      expect(updated.estimateSource, isNull);
    });

    test('updateTicket with neither *Edited flag leaves an existing '
        'aiSuggested source completely untouched when some other field '
        'is edited — regression test for the "editing title relocks an '
        'AI suggestion" bug', () async {
      await repository.createTicket(buildTicket(id: '1'));
      await repository.applyEstimationSuggestion(
        '1',
        complexity: (value: TicketComplexity.medium, lowConfidence: false),
        estimate: (value: 45, lowConfidence: true),
      );
      final aiSuggested = await repository.getTicketById('1');
      expect(aiSuggested!.complexitySource, TicketEstimationSource.aiSuggested);
      expect(
        aiSuggested.estimateSource,
        TicketEstimationSource.aiSuggestedLowConfidence,
      );

      // Editing an unrelated field (title) — complexity/estimate merely
      // carry through unchanged, neither *Edited flag is passed.
      await repository.updateTicket(aiSuggested.copyWith(title: 'New title'));
      final afterTitleEdit = await repository.getTicketById('1');

      expect(afterTitleEdit!.title, 'New title');
      expect(afterTitleEdit.complexity, TicketComplexity.medium);
      expect(
        afterTitleEdit.complexitySource,
        TicketEstimationSource.aiSuggested,
      );
      expect(afterTitleEdit.estimate, 45);
      expect(
        afterTitleEdit.estimateSource,
        TicketEstimationSource.aiSuggestedLowConfidence,
      );
    });

    test('updateTicket with complexityEdited: true re-locks an aiSuggested '
        'complexity to manual even when the selected value is unchanged '
        '(the "confirm an AI suggestion" case)', () async {
      await repository.createTicket(buildTicket(id: '1'));
      await repository.applyEstimationSuggestion(
        '1',
        complexity: (value: TicketComplexity.medium, lowConfidence: false),
      );
      final aiSuggested = await repository.getTicketById('1');

      await repository.updateTicket(
        aiSuggested!.copyWith(complexity: () => TicketComplexity.medium),
        complexityEdited: true,
      );
      final confirmed = await repository.getTicketById('1');

      expect(confirmed!.complexity, TicketComplexity.medium);
      expect(confirmed.complexitySource, TicketEstimationSource.manual);
    });

    test('clearing complexity/estimate on updateTicket clears the source '
        'back to null', () async {
      final now = DateTime(2026, 1, 1);
      await repository.createTicket(
        Ticket(
          id: '1',
          ticketId: '',
          type: TicketType.task,
          title: 'Sized ticket',
          status: TicketStatus.backlog,
          complexity: TicketComplexity.small,
          estimate: 30,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final persisted = await repository.getTicketById('1');
      expect(persisted!.complexitySource, TicketEstimationSource.manual);
      expect(persisted.estimateSource, TicketEstimationSource.manual);

      await repository.updateTicket(
        persisted.copyWith(
          complexity: () => null,
          estimate: () => null,
        ),
      );
      final updated = await repository.getTicketById('1');

      expect(updated!.complexity, isNull);
      expect(updated.complexitySource, isNull);
      expect(updated.estimate, isNull);
      expect(updated.estimateSource, isNull);
    });

    test('createTicket with complexity/estimate already set stamps manual '
        'from the moment of creation', () async {
      final now = DateTime(2026, 1, 1);
      await repository.createTicket(
        Ticket(
          id: '1',
          ticketId: '',
          type: TicketType.task,
          title: 'Sized at creation',
          status: TicketStatus.backlog,
          complexity: TicketComplexity.large,
          estimate: 200,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final found = await repository.getTicketById('1');

      expect(found!.complexitySource, TicketEstimationSource.manual);
      expect(found.estimateSource, TicketEstimationSource.manual);
    });

    test('createTicket with complexity/estimate left unset leaves both '
        'sources null', () async {
      await repository.createTicket(buildTicket(id: '1'));
      final found = await repository.getTicketById('1');

      expect(found!.complexitySource, isNull);
      expect(found.estimateSource, isNull);
    });
  });

  group('applyEstimationSuggestion', () {
    test('writes only the requested field(s), leaving the other and '
        'updatedAt untouched', () async {
      await repository.createTicket(buildTicket(id: '1'));
      final before = (await repository.getTicketById('1'))!.updatedAt;

      await repository.applyEstimationSuggestion(
        '1',
        complexity: (value: TicketComplexity.medium, lowConfidence: false),
      );
      final afterComplexityOnly = await repository.getTicketById('1');

      expect(afterComplexityOnly!.complexity, TicketComplexity.medium);
      expect(
        afterComplexityOnly.complexitySource,
        TicketEstimationSource.aiSuggested,
      );
      expect(afterComplexityOnly.estimate, isNull);
      expect(afterComplexityOnly.estimateSource, isNull);
      expect(afterComplexityOnly.updatedAt, before);

      await repository.applyEstimationSuggestion(
        '1',
        estimate: (value: 45, lowConfidence: true),
      );
      final afterBoth = await repository.getTicketById('1');

      expect(afterBoth!.estimate, 45);
      expect(
        afterBoth.estimateSource,
        TicketEstimationSource.aiSuggestedLowConfidence,
      );
      // The earlier complexity write is untouched by this second call.
      expect(afterBoth.complexity, TicketComplexity.medium);
      expect(
        afterBoth.complexitySource,
        TicketEstimationSource.aiSuggested,
      );
      expect(afterBoth.updatedAt, before);
    });

    test('a lowConfidence complexity suggestion stamps '
        'aiSuggestedLowConfidence', () async {
      await repository.createTicket(buildTicket(id: '1'));

      await repository.applyEstimationSuggestion(
        '1',
        complexity: (value: TicketComplexity.small, lowConfidence: true),
      );
      final found = await repository.getTicketById('1');

      expect(
        found!.complexitySource,
        TicketEstimationSource.aiSuggestedLowConfidence,
      );
    });
  });

  group('getExecutionTokenTotals', () {
    late DriftCommentRepository commentRepository;

    setUp(() {
      commentRepository = DriftCommentRepository(database);
    });

    Future<void> addAiComment(
      String chatId, {
      int? inputTokens,
      int? outputTokens,
    }) {
      return commentRepository.addComment(
        TicketComment(
          id: '',
          ticketId: chatId,
          content: 'reply',
          authorType: CommentAuthorType.ai,
          inputTokens: inputTokens,
          outputTokens: outputTokens,
          createdAt: DateTime(2026, 1, 1),
        ),
      );
    }

    test('sums multiple execution chats under the same task together',
        () async {
      await repository.createTicket(buildTicket(id: 'task-1'));
      final chatA = Ticket(
        id: 'chat-a',
        ticketId: '',
        type: TicketType.chat,
        title: 'Coding Execution — Test ticket',
        status: TicketStatus.backlog,
        parentId: 'task-1',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final chatB = Ticket(
        id: 'chat-b',
        ticketId: '',
        type: TicketType.chat,
        title: 'Coding Execution — Test ticket (continued)',
        status: TicketStatus.backlog,
        parentId: 'task-1',
        createdAt: DateTime(2026, 1, 2),
        updatedAt: DateTime(2026, 1, 2),
      );
      await repository.createTicket(chatA);
      await repository.createTicket(chatB);
      await addAiComment('chat-a', inputTokens: 100, outputTokens: 200);
      await addAiComment('chat-b', inputTokens: 50, outputTokens: 25);

      final totals = await repository.getExecutionTokenTotals(['task-1']);

      expect(totals['task-1'], 375);
    });

    test('a task with zero execution chats is absent from the result map',
        () async {
      await repository.createTicket(buildTicket(id: 'task-1'));

      final totals = await repository.getExecutionTokenTotals(['task-1']);

      expect(totals.containsKey('task-1'), isFalse);
    });

    test('null inputTokens/outputTokens on a comment contribute 0',
        () async {
      await repository.createTicket(buildTicket(id: 'task-1'));
      final chat = Ticket(
        id: 'chat-a',
        ticketId: '',
        type: TicketType.chat,
        title: 'Coding Execution — Test ticket',
        status: TicketStatus.backlog,
        parentId: 'task-1',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await repository.createTicket(chat);
      // A system comment with no token usage recorded.
      await commentRepository.addComment(
        TicketComment(
          id: '',
          ticketId: 'chat-a',
          content: 'context',
          authorType: CommentAuthorType.system,
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      await addAiComment('chat-a', inputTokens: 10, outputTokens: null);

      final totals = await repository.getExecutionTokenTotals(['task-1']);

      expect(totals['task-1'], 10);
    });

    test('a multi-id batch query returns entries only for ids with data',
        () async {
      await repository.createTicket(buildTicket(id: 'task-1'));
      await repository.createTicket(buildTicket(id: 'task-2'));
      final chat = Ticket(
        id: 'chat-a',
        ticketId: '',
        type: TicketType.chat,
        title: 'Coding Execution — Test ticket',
        status: TicketStatus.backlog,
        parentId: 'task-1',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await repository.createTicket(chat);
      await addAiComment('chat-a', inputTokens: 40, outputTokens: 10);

      final totals = await repository.getExecutionTokenTotals([
        'task-1',
        'task-2',
      ]);

      expect(totals, {'task-1': 50});
    });
  });

  group('applyTokenPrediction', () {
    test('persists both fields together and touches no other field',
        () async {
      await repository.createTicket(buildTicket(id: '1'));
      final before = await repository.getTicketById('1');

      await repository.applyTokenPrediction('1', low: 12000, high: 34000);
      final after = await repository.getTicketById('1');

      expect(after!.predictedExecutionTokensLow, 12000);
      expect(after.predictedExecutionTokensHigh, 34000);
      expect(after.title, before!.title);
      expect(after.status, before.status);
      expect(after.priority, before.priority);
      expect(after.updatedAt, before.updatedAt);
    });
  });
}
